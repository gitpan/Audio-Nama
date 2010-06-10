{
package Audio::Nama::Insert;
use Modern::Perl;
use Carp;
no warnings qw(uninitialized redefine);
our $VERSION = 0.1;
our ($debug);
local $debug = 0;
use vars qw(%by_index);
use Audio::Nama::Object qw(
	insert_type
	n
	class
	send_type
	send_id
	return_type
	return_id
	wet_track
	dry_track
	tracks
	track
	wetness
	wet_vol
	dry_vol
);
# tracks: deprecated

initialize();

sub initialize { %by_index = () }

sub idx { # return first free index
	my $n = 0;
	while (++$n){
		return $n if not $by_index{$n}
	}
}

sub wet_name {
	my $self = shift;
	# use the field if available for backward compatibility (pre 1.054)
	$self->{wet_name} || join('-', $self->track, $self->n, 'wet'); 
}
sub dry_name {
	my $self = shift;
	# use the field if available for backward compatibility (pre 1.054)
	$self->{dry_name} || join('-', $self->track, $self->n, 'dry'); 
}
sub new {
	my $class = shift;
	my %vals = @_;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	$vals{n} ||= idx(); 
	my $self = bless { 
					class	=> $class, 	# for restore
					wetness		=> 100,
					%vals,
								}, $class;
	my $name = $vals{track};
	my $wet = Audio::Nama::SlaveTrack->new( 
				name => $self->wet_name,
				target => $name,
				group => 'Insert',
				rw => 'REC',
				hide => 1,
			);
	my $dry = Audio::Nama::SlaveTrack->new( 
				name => $self->dry_name,
				target => $name,
				group => 'Insert',
				hide => 1,
				rw => 'REC');
	map{ Audio::Nama::remove_effect($_)} $wet->vol, $wet->pan, $dry->vol, $dry->pan;

	$self->{dry_vol} = Audio::Nama::Text::t_add_effect($dry, 'ea',[0]);
	$self->{wet_vol} = Audio::Nama::Text::t_add_effect($wet, 'ea',[100]);
	$by_index{$self->n} = $self;
}

# method name for track field holding insert

sub type { (ref $_[0]) =~ /Pre/ ? 'prefader_insert' : 'postfader_insert' }

sub remove {
	my $self = shift;
	$Audio::Nama::tn{ $self->wet_name }->remove;
	$Audio::Nama::tn{ $self->dry_name }->remove;
	my $type = $self->type;

	# look for track that has my id and delete it
	my ($track) = grep{$_->$type == $self->n} values %Audio::Nama::Track::by_name;
	$track->set(  $type => undef );

	# delete my own index entry
	delete $by_index{$self->n};
}
	
# subroutine
#
sub add_insert {
	my ($type, $send_id, $return_id) = @_;
	# $type : prefader_insert | postfader_insert
	say "\n",$Audio::Nama::this_track->name , ": adding $type\n";
	my $old_this_track = $Audio::Nama::this_track;
	my $t = $Audio::Nama::this_track;
	my $name = $t->name;

	# the input fields will be ignored, since the track will get input
	# via the loop device track_insert
	
	my $class =  $type =~ /pre/ ? 'Audio::Nama::PreFaderInsert' : 'Audio::Nama::PostFaderInsert';
	
	my $i = $class->new( 
		track => $t->name,
		send_type 	=> Audio::Nama::dest_type($send_id),
		send_id	  	=> $send_id,
		return_type 	=> Audio::Nama::dest_type($return_id),
		return_id	=> $return_id,
	);
	if (! $i->{return_id}){
		$i->{return_type} = $i->{send_type};
		$i->{return_id} =  $i->{send_id} if $i->{return_type} eq 'jack_client';
		$i->{return_id} =  $i->{send_id} + 2 if $i->{return_type} eq 'soundcard';
	}
	$t->$type and $by_index{$t->$type}->remove;
	$t->set($type => $i->n); 
	$Audio::Nama::this_track = $old_this_track;
}
sub get_id {
	my ($track, $prepost) = @_;
	my %id = (pre => $track->prefader_insert,
			 post => $track->postfader_insert);
	#print "prepost: $prepost\n";
	$prepost = $id{pre} ? 'pre' : 'post'
		if (! $prepost and ! $id{pre} != ! $id{post} );
	$id{$prepost};;
}
}
{
package Audio::Nama::PostFaderInsert;
use Modern::Perl; use Carp; our @ISA = qw(Audio::Nama::Insert); our $debug;
sub add_paths {

	# Since this routine will be called after expand_graph, 
	# we can be sure that every track vertex will connect to 
	# to a single edge, either loop or an output 
	
	my ($self, $g, $name) = @_;
	no warnings qw(uninitialized);
	#my $debug = 1;
	$debug and say "add_insert for track: $name";

	my $t = $Audio::Nama::tn{$name}; 


	$debug and say "insert structure:", $self->dump;

	my ($successor) = $g->successors($name);

	# successor will be either a loop, device or JACK port
	# i.e. can accept multiple signals

	$g->delete_edge($name, $successor);
	my $loop = "$name\_insert_post";
	my $wet = $Audio::Nama::tn{$self->wet_name};
	my $dry = $Audio::Nama::tn{$self->dry_name};

	$debug and say "found wet: ", $wet->name, " dry: ",$dry->name;

	# wet send path (no track): track -> loop -> output
	
	my @edge = ($loop, Audio::Nama::output_node($self->{send_type}));
	$debug and say "edge: @edge";
	Audio::Nama::Graph::add_path($name, @edge);
	$g->set_vertex_attributes($loop, {n => $t->n});
	$g->set_edge_attributes(@edge, { 
		send_id => $self->{send_id},
		width => 2,
	});
	# wet return path: input -> wet_track (slave) -> successor
	
	# we override the input with the insert's return source

	$g->set_vertex_attributes($wet->name, {
				width => 2, # default for cooked
				mono_to_stereo => '', # override
				source_type => $self->{return_type},
				source_id => $self->{return_id},
	});
	Audio::Nama::Graph::add_path(Audio::Nama::input_node($self->{return_type}), $wet->name, $successor);

	# connect dry track to graph
	
	Audio::Nama::Graph::add_path($loop, $dry->name, $successor);
	}
	
}
{
package Audio::Nama::PreFaderInsert;
use Modern::Perl; use Carp; our @ISA = qw(Audio::Nama::Insert); our $debug;
sub add_paths {

# --- predecessor --+-- wet-send    wet-return ---+-- insert_pre -- track
#                   |                             |
#                   +-------------- dry ----------+
           

	my ($self, $g, $name) = @_;
	no warnings qw(uninitialized);
	#my $debug = 1;
	$debug and say "add_insert for track: $name";

	my $t = $Audio::Nama::tn{$name}; 


	$debug and say "insert structure:", $self->dump;

		my ($predecessor) = $g->predecessors($name);
		$g->delete_edge($predecessor, $name);
		my $loop = "$name\_insert_pre";
		my $wet = $Audio::Nama::tn{$self->wet_name};
		my $dry = $Audio::Nama::tn{$self->dry_name};

		$debug and say "found wet: ", $wet->name, " dry: ",$dry->name;


		#pre:  wet send path (no track): predecessor -> output

		my @edge = ($predecessor, Audio::Nama::output_node($self->{send_type}));
		$debug and say "edge: @edge";
		Audio::Nama::Graph::add_path(@edge);
		$g->set_edge_attributes(@edge, { 
			send_id => $self->{send_id},
			send_type => $self->{send_type},
			mono_to_stereo => '', # override
			width => $t->width,
			track => $name,
			n => $t->n,
		});

		#pre:  wet return path: input -> wet_track (slave) -> loop

		
		# we override the input with the insert's return source

		$g->set_vertex_attributes($wet->name, {
				width => $t->width, 
				mono_to_stereo => '', # override
				source_type => $self->{return_type},
				source_id => $self->{return_id},
		});
		$g->set_vertex_attributes($dry->name, {
				mono_to_stereo => '', # override
		});
		Audio::Nama::Graph::add_path(Audio::Nama::input_node($self->{return_type}), $wet->name, $loop);

		# connect dry track to graph
		#
		# post: dry path: loop -> dry -> successor
		# pre: dry path:  predecessor -> dry -> loop
		
		Audio::Nama::Graph::add_path($predecessor, $dry->name, $loop, $name);
	}
	
}
1;