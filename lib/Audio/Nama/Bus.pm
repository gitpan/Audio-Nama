# ------------  Bus --------------------

package Audio::Nama::Bus;
use Modern::Perl; use Carp; 
use Audio::Nama::Log qw(logsub logpkg);
use Audio::Nama::Globals qw(:trackrw); 
our @ISA = qw( Audio::Nama::Object );

# share the following variables with subclasses

our $VERSION = 1.0;
our (%by_name);
use Audio::Nama::Object qw(
					name
					rw
					version 
					send_type
					send_id
					engine_group
					class

					);
sub initialize { 
	%by_name = (); 
};
sub new {
	my $class = shift;
	my %vals = @_;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	if (! $vals{name}){
		Audio::Nama::throw("missing bus name");
		return
	}
	if ( $by_name{$vals{name}} ){ 
		Audio::Nama::throw("$vals{name}: bus name already exists. Skipping.")
			unless $Audio::Nama::quiet;
		return;
	}
	my $bus = bless { 
		class => $class, # for serialization, may be overridden
		rw   	=> MON, # for group control
		@_ }, $class;
	$by_name{$bus->name} = $bus;
}
sub group { $_[0]->name }


sub tracks { # returns list of track names in bus
	my $bus = shift;
	map{ $_->name } $bus->track_o;
}
sub track_o { 
	my $bus = shift;
	grep{ $_->group eq $bus->name } Audio::Nama::all_tracks();
}
sub last {
	#logpkg(__FILE__,__LINE__,'debug', "group: @_");
	my $bus = shift;
	my $max = 0;
	map{ 
		my $track = $_;
		my $last;
		$last = $track->last || 0;
		#print "track: ", $track->name, ", last: $last\n";

		$max = $last if $last > $max;

	} $bus->track_o;
	$max;
}

sub remove { Audio::Nama::throw($_[0]->name, " is system bus. No can remove.") }

{ my %allows = (REC => 'REC/MON', MON => MON, OFF => 'OFF');
sub allows { $allows{ $_[0]->rw } }
}
{ my %forces = (
		REC => 'REC (allows REC/MON)', 
		MON => 'MON (forces REC to MON)', 
		OFF => 'OFF (enforces OFF)'
 );
sub forces { $forces{ $_[0]->rw } }
}
	
## class methods

# sub buses, and Main
sub all { grep{ ! $Audio::Nama::config->{_is_system_bus}->{$_->name} } values %by_name };

sub overall_last { 
	my $max = 0;
	map{ my $last = $_->last; $max = $last if $last > $max  } all();
	$max;
}
sub settings_line {
	
	my ($mix,$bus) = @_;
	
	my $nothing = '-' x 77 . "\n";
	#return if $maybe_mix->name eq 'Master' or $maybe_mix->group eq 'Mastering';
	return unless defined $mix;

	my ($bustype) = $bus->class =~ /(\w+)$/;
	my $line = join " ", $bustype ,$bus->name,"is",$bus->forces;
	$line   .= " Version setting".$bus->version if $bus->version;
	#$line   .= "feeds", 
	$line .= " Mix track is ". $mix->rw;
	$line = "------[$line]";
	$line .= '-' x (77 - length $line);
	$line .= "\n";
	$line
}
	
sub trackslist {
	my $bus = shift;
	my $mix = $Audio::Nama::tn{$bus->send_id};
	my @list = ($mix,$bus);
	push @list, map{$Audio::Nama::tn{$_}} ($mix->name, $bus->tracks);
	\@list;
}

sub apply {}  # base class does no routing of its own


### subclasses
{
package Audio::Nama::SubBus;
use Modern::Perl; use Carp; our @ISA = 'Audio::Nama::Bus';
use Audio::Nama::Log qw(logsub logpkg);
use Audio::Nama::Util qw(input_node);
use Audio::Nama::Globals qw(:trackrw);

# connect source --> member_track --> mix_track

sub output_is_connectable {
 	my $bus = shift;

	# Either the bus's mix track is set to REC or MON
 	
 	$bus->send_type eq 'track' and $Audio::Nama::tn{$bus->send_id}->rec_status =~ /REC|MON/

	# Or, during mixdown, we connect bus member tracks to Master
	# even tho Master may be set to OFF
	
	or $bus->send_type eq 'track' 
				and $bus->send_id eq 'Master' 
				and $Audio::Nama::tn{Mixdown}->rec_status eq 'REC'
	
	# or we are connecting directly to a loop device
	or $bus->send_type eq 'loop' and $bus->send_id =~ /^\w+_(in|out)$/;
}

sub apply {
	no warnings 'uninitialized';
	my ($bus, $g)  = @_;
	logpkg(__FILE__,__LINE__,'debug', "bus ". $bus->name. ": applying routes");
	logpkg(__FILE__,__LINE__,'debug', "Bus destination is type: $bus->{send_type}, id: $bus->{send_id}");
	map{ 
		# connect member track input paths
		logpkg(__FILE__,__LINE__,'debug', "track ".$_->name);
		my @path = $_->input_path;
		$g->add_path(@path) if @path;
		logpkg(__FILE__,__LINE__,'debug',"input path: @path") if scalar @path;

		logpkg(__FILE__,__LINE__,'debug', join " ", "bus output:", $_->name, $bus->send_id);

		# connect member track outputs to target
		# disregard Master track rec_status when connecting
		# Main bus during mixdown handling

		Audio::Nama::Graph::add_path_for_send($g, $_->name, $bus->send_type, $bus->send_id )
			if $bus->output_is_connectable;
		
		# add paths for recording
		
		Audio::Nama::Graph::add_path_for_rec($g,$_) 
			if $_->rec_status eq REC
				and ! $Audio::Nama::mode->preview and ! $Audio::Nama::mode->doodle;

	} grep {$_->rec_status ne OFF} $bus->track_o;
}
sub remove {
	my $bus = shift;

	# all tracks returned to Main group
	map{$_->set(group => 'Main') } $bus->track_o;

	my $mix_track = $Audio::Nama::tn{$bus->name};

	if ( defined $mix_track ){
	 
		$mix_track->unbusify;
	
		# remove mix track unless it has some WAV files

		$mix_track->remove unless scalar @{ $mix_track->versions };
	}

	# remove bus from index
	
	delete $Audio::Nama::bn{$bus->name};
} 
}
{
package Audio::Nama::SendBusRaw;
use Modern::Perl; use Carp; our @ISA = 'Audio::Nama::Bus';
use Audio::Nama::Log qw(logsub logpkg);
sub apply {
	my $bus = shift;
	map{ 
		my @input_path = $_->input_path;
		$Audio::Nama::g->add_edge(@input_path);
		$Audio::Nama::g->set_edge_attributes( @input_path, 
			{ width => $Audio::Nama::tn{$_->target}->width });
		my @edge = ($_->name, Audio::Nama::output_node($bus->send_type));
		$Audio::Nama::g->add_edge(@edge);
		$Audio::Nama::g->set_edge_attributes( @edge, { 
			send_id => $bus->send_id,
			width => 2 }); # force to stereo 
	} grep{ $_->input_path } $bus->track_o;
}
sub remove {
	my $bus = shift;

	# delete all tracks
	map{$_->remove } $bus->track_o;

	# remove bus
	delete $by_name{$bus->name};
}
}
{
package Audio::Nama::SendBusCooked;
use Audio::Nama::Log qw(logsub logpkg);
use Modern::Perl; use Carp; our @ISA = 'Audio::Nama::SendBusRaw';

# graphic routing: target -> slave -> bus_send_type

sub apply {
	my $bus = shift;
	my $g = shift;
	map{ my @edge = ($_->name, Audio::Nama::output_node($bus->send_type));
		 $g->add_path( $_->target, @edge);
		 $g->set_edge_attributes( @edge, { 
				send_type => $bus->send_type,
				send_id => $bus->send_id,
				width => 2})
	} $bus->track_o;
}

}

# ---------- Bus routines --------
{
package Audio::Nama;
use Modern::Perl; use Carp;
use Audio::Nama::Util qw(dest_type);
our (
	$this_track,
	$this_bus,
	%tn,
	%bn,
);

sub set_current_bus {
	my $track = shift || ($this_track ||= $tn{Master});

	return unless $track; # needed for test environment

	# The current sequence changes when the user touches a
	# track that belongs to another sequence.
	
	$this_sequence = $bn{$track->group} if (ref $bn{$track->group}) =~ /Sequence/;

	my $bus_name = 
		$track->name =~ /Master|Mixdown/ 	
		? 'Main'
		: $track->is_mix_track()			
			? $track->name 
			: $track->group;
	
	select_bus($bus_name);
}
sub select_bus {
	my $name = shift;
	my $bus = $bn{$name} or return;
	$this_bus = $name;
	$this_bus_o = $bus;
}
sub add_bus {
	my ($name, @args) = @_; 
	
	Audio::Nama::SubBus->new( 
		name => $name, 
		send_type => 'track',
		send_id	 => $name,
		) unless $Audio::Nama::Bus::by_name{$name};

	@args = ( 
		rw 			=> MON,
		@args
	);

	$tn{$name} and Audio::Nama::pager_newline( qq($name: setting as mix track for bus "$name"));

	my $track = $tn{$name}// add_track($name, width => 2);

	$track->set( @args );
	
}
	
sub add_submix {

	my ($name, $dest_id, $bus_type) = @_;
	my $dest_type = dest_type( $dest_id );

	# dest_type: soundcard | jack_client | loop | jack_port | jack_multi
	
	logpkg(__FILE__,__LINE__,'debug',"name: $name, dest_type: $dest_type, dest_id: $dest_id");
	if ($bn{$name} and (ref $bn{$name}) !~ /SendBus/){
		Audio::Nama::throw($name,": bus name already in use. Aborting."), return;
	}
	if ($bn{$name}){
		Audio::Nama::pager_newline( qq(monitor bus "$name" already exists.  Updating with new tracks.) );
	} else {
	my @args = (
		name => $name, 
		send_type => $dest_type,
		send_id	 => $dest_id,
	);

	my $class = $bus_type eq 'cooked' ? 'Audio::Nama::SendBusCooked' : 'Audio::Nama::SendBusRaw';
	my $bus = $class->new( @args );

	$bus or carp("can't create bus!\n"), return;

	}
	map{ Audio::Nama::EarTrack->new(	name => "$name\_$_", # BusName_TrackName
							rw => MON,
							target => $_,
							group  => $name,
							width => 2,
							hide	=> 1,
						)
   } $bn{Main}->tracks;
		
}

	
sub update_submix {
	my $name = shift;
		add_submix( $name, 
						 $bn{$name}->send_id),
						 "dummy",
}
sub remove_submix_helper_tracks {
	my $name = shift;
	#say "got name: $name";
	my @submixes = submixes(); 
	#say "got submixes:", Dumper \@submixes;
	for my $sm ( @submixes ){ 
		my $to_remove = join '_', $sm->name, $name;
		#say "to_remove: $to_remove";
		local $quiet;
		$quiet++;
		for my $name ($sm->tracks) { 
			$tn{$name}->remove, last if $name eq $to_remove
		}
	}

}
sub submixes { grep { (ref $_) =~ /SendBusCooked/ } values %Audio::Nama::Bus::by_name }

}
1;
__END__