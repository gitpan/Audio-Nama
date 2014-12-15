# ------------  Bus --------------------


package Audio::Nama::Bus;
use Modern::Perl; use Carp; 
our @ISA = qw( Audio::Nama::Object );

# share the following variables with subclasses

our $VERSION = 1.0;
our (%by_name, $logger);
use Audio::Nama::Object qw(
					name
					rw
					version 
					send_type
					send_id
					class

					);
sub initialize { 
	%by_name = (); 
	$logger = Log::Log4perl->get_logger("Audio::Nama::Bus");
	
};
sub new {
	my $class = shift;
	my %vals = @_;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	if (! $vals{name}){
		say "missing bus name"; 
		return
	}
	if ( $by_name{$vals{name}} ){ 
		say "$vals{name}: bus name already exists. Skipping.";
		return;
	}
	my $bus = bless { 
		class => $class, # for serialization, may be overridden
		rw   	=> 'REC', # for group control
		@_ }, $class;
	$by_name{$bus->name} = $bus;
}
sub group { $_[0]->name }


sub tracks { # returns list of track names in bus
	my $bus = shift;
	map{ $_->name } grep{ $_->group eq $bus->name } Audio::Nama::Track::all();
}

sub last {
	#$logger->debug( "group: @_");
	my $group = shift;
	my $max = 0;
	map{ 
		my $track = $_;
		my $last;
		$last = $track->last || 0;
		#print "track: ", $track->name, ", last: $last\n";

		$max = $last if $last > $max;

	}	map { $Audio::Nama::Track::by_name{$_} } $group->tracks;
	$max;
}

sub remove { say $_[0]->name, " is system bus. No can remove." }

{ my %allows = (REC => 'REC/MON', MON => 'MON', OFF => 'OFF');
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
use Audio::Nama::Util qw(input_node);
use Try::Tiny;

# graphic routing: track -> mix_track

{

my $g;
my $bus;
my %dispatch = (

	# connect member tracks to  mix track
	# if mix track is known and mix track is set to REC
	track => sub { $Audio::Nama::tn{$bus->send_id}->rec_status eq 'REC'  },

	# connect loop device, with verification
	loop  => sub { $bus->send_id =~ /^\w+_(in|out)$/ },
);

sub apply {
	no warnings 'uninitialized';
	$bus = shift;
	$g = shift;
	$logger->debug( "bus ". $bus->name. ": applying routes");
	$logger->debug( "Expected track as bus destination, found type: (",
		$bus->send_type, ") id: (", $bus->send_id, q[)] );
	map{ 
		# connect signal sources to tracks
		$logger->debug( "track ".$_->name);
		my @path = $_->input_path;
		$g->add_path(@path) if @path;
		$logger->debug("input path: @path") if scalar @path;

		try{ $logger->debug( join " ", "bus output:", $_->name, $bus->send_id) };
		$g->add_edge($_->name, $bus->send_id)
			if 	try { $dispatch{$bus->send_type}->() } 
			catch {  warn "caught error: $_" } ;
		
		# add paths for recording
		#
		#
		# say "rec status: ",$_->rec_status;
		# say "rec defeat: ",$_->rec_defeat; 
		# say q($mode->{preview}: ),$Audio::Nama::mode->{preview};
		# say "result", $_->rec_status eq 'REC' and ! $_->rec_defeat
		# 		and ! ( $Audio::Nama::mode->{preview} eq 'doodle' );
			
		Audio::Nama::Graph::add_path_for_rec($g,$_) 
			if $_->rec_status eq 'REC' 
			and ! $_->rec_defeat
				and $Audio::Nama::mode->{preview} !~ /doodle|preview/ ;

	} grep{ $_->group eq $bus->group} Audio::Nama::Track::all()
}
}
sub remove {
	my $bus = shift;

	# all tracks returned to Main group
	map{$Audio::Nama::tn{$_}->set(group => 'Main') } $by_name{$bus->name}->tracks;

	my $mix_track = $Audio::Nama::tn{$bus->name};

	if ( defined $mix_track ){
	 
		$mix_track->unbusify;
	
		# remove mix track unless it has some WAV files

		$mix_track->remove unless scalar @{ $mix_track->versions };
	}

	# remove bus from index
	
	delete $by_name{$bus->name};
} 
}
{
package Audio::Nama::MasterBus;
use Modern::Perl; use Carp; our @ISA = 'Audio::Nama::SubBus';
sub apply {
	my ($bus,$g) = @_;
	$bus->SUPER::apply($g);
	map { $g->add_edge($_->name, $bus->send_id) } 
	grep{ $_->group eq $bus->group} 
	Audio::Nama::Track::all()
}
}
{
package Audio::Nama::SendBusRaw;
use Modern::Perl; use Carp; our @ISA = 'Audio::Nama::Bus';
sub apply {
	my $bus = shift;
	map{ 
		$Audio::Nama::g->add_edge($_->input_path);
		my @edge = ($_->name, Audio::Nama::output_node($bus->send_type));
		$Audio::Nama::g->add_edge(@edge);
		$Audio::Nama::g->set_edge_attributes( @edge, { 
			send_id => $bus->send_id,
			width => 2 }); # force to stereo 
	} grep{ $_->group eq $bus->group and $_->input_path} Audio::Nama::Track::all()
}
sub remove {
	my $bus = shift;

	# delete all (slave) tracks
	map{$Audio::Nama::tn{$_}->remove } $by_name{$bus->name}->tracks;

	# remove bus
	delete $by_name{$bus->name};
}
}
{
package Audio::Nama::SendBusCooked;
use Modern::Perl; use Carp; our @ISA = 'Audio::Nama::SendBusRaw';

# graphic routing: target -> slave -> bus_send_type

sub apply {
	my $bus = shift;
	my $g = shift;
	map{ my @edge = ($_->name, Audio::Nama::output_node($bus->send_type));
		 $g->add_path( $_->target, @edge);
		 $g->set_edge_attributes( @edge, { 
				send_id => $bus->send_id,
				width => 2})
	} grep{ $_->group eq $bus->group} Audio::Nama::Track::all()
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
	return unless $track;
	#say "track: $track";
	#say "this_track: $this_track";
	#say "master: $tn{Master}";
	if( $track->name =~ /Master|Mixdown/){ $this_bus = 'Main' }
	elsif( $bn{$track->name} ){$this_bus = $track->name }
	else { $this_bus = $track->group }
}
sub add_sub_bus {
	my ($name, @args) = @_; 
	
	Audio::Nama::SubBus->new( 
		name => $name, 
		send_type => 'track',
		send_id	 => $name,
		) unless $Audio::Nama::Bus::by_name{$name};

	# create mix track
	@args = ( 
		width 		=> 2,     # default to stereo 
		rec_defeat	=> 1,     # set to rec_defeat (don't record signal)
		rw 			=> 'REC', # essentially 'on'
		@args
	);

	$tn{$name} and say qq($name: setting as mix track for bus "$name");

	my $track = $tn{$name} // add_track($name);

	# convert host track to mix track
	
	$track->set(was_class => ref $track); # save the current track (sub)class
	$track->set_track_class('Audio::Nama::MixTrack'); 
	$track->set( @args );
	
}
	
sub add_send_bus {

	my ($name, $dest_id, $bus_type) = @_;
	my $dest_type = dest_type( $dest_id );

	# dest_type: soundcard | jack_client | loop | jack_port | jack_multi
	
	print "name: $name: dest_type: $dest_type dest_id: $dest_id\n";
	if ($bn{$name} and (ref $bn{$name}) !~ /SendBus/){
		say($name,": bus name already in use. Aborting."), return;
	}
	if ($bn{$name}){
		say qq(monitor bus "$name" already exists. Updating with new tracks.");
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
	map{ Audio::Nama::SlaveTrack->new(	name => "$name\_$_", # BusName_TrackName
							rw => 'MON',
							target => $_,
							group  => $name,
						)
   } $bn{Main}->tracks;
		
}

	
sub update_send_bus {
	my $name = shift;
		add_send_bus( $name, 
						 $bn{$name}->send_id),
						 "dummy",
}

} # end package

1;
__END__