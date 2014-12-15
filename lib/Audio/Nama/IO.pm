package Audio::Nama;
our (%tn, $jack, $config);

# ---------- IO -----------

# 
# IO objects for writing Ecasound chain setup file
#
# Object values can come from three sources:
# 
# 1. As arguments to the constructor new() while walking the
#    routing graph:
#      + assigned by dispatch: chain_id, loop_id, track, etc.
#      + override by graph node (higher priority)
#      + override by graph edge (highest priority)
# 2. (sub)class methods called as $object->method_name
#      + defined as _method_name (access via AUTOLOAD, overrideable by constructor)
#      + defined as method_name  (not overrideable)
# 3. AUTOLOAD
#      + any other method calls are passed to the the associated track
#      + illegal track method call generate an exception

package Audio::Nama::IO;
use Modern::Perl; use Carp;
use Data::Dumper::Concise;
our $VERSION = 1.0;

# provide following vars to all packages
our ($config, $jack, %tn);
our (%by_name); # index for $by_name{trackname}->{input} = $object
use Audio::Nama::Globals qw($config $jack %tn $setup);
use Try::Tiny;

sub initialize { %by_name = () }

# we will use the following to map from graph node names
# to IO class names

our %io_class = qw(
	null_in					Audio::Nama::IO::from_null
	null_out				Audio::Nama::IO::to_null
	soundcard_in 			Audio::Nama::IO::from_soundcard
	soundcard_out 			Audio::Nama::IO::to_soundcard
	soundcard_device_in 	Audio::Nama::IO::from_soundcard_device
	soundcard_device_out 	Audio::Nama::IO::to_soundcard_device
	wav_in 					Audio::Nama::IO::from_wav
	wav_out 				Audio::Nama::IO::to_wav
	loop_source				Audio::Nama::IO::from_loop
	loop_sink				Audio::Nama::IO::to_loop
	jack_manual_in			Audio::Nama::IO::from_jack_port
	jack_manual_out			Audio::Nama::IO::to_jack_port
	jack_ports_list_in		Audio::Nama::IO::from_jack_port
	jack_ports_list_out		Audio::Nama::IO::to_jack_port
	jack_multi_in			Audio::Nama::IO::from_jack_multi
	jack_multi_out			Audio::Nama::IO::to_jack_multi
	jack_client_in			Audio::Nama::IO::from_jack_client
	jack_client_out			Audio::Nama::IO::to_jack_client
	);

### class descriptions

# === CLASS Audio::Nama::IO::from_jack_port ===
#
# is triggered by source_type codes: 
#
#  + jack_manual_in 
#  + jack_ports_list_in
#
# For track 'piano', the class creates an input similar to:
#
# -i:jack,,piano_in 
#
# which receives input from JACK node: 
#
#  + ecasound:piano_in,
# 
# If piano is stereo, the actual ports will be:
#
#  + ecasound:piano_in_1
#  + ecasound:piano_in_2

# (CLASS Audio::Nama::IO::to_jack_port is similar)

### class definition

our $AUTOLOAD;

# add underscore to field names so that regular method
# access will go through AUTOLOAD

# we add an underscore to each key 

use Audio::Nama::Object qw(track_ chain_id_ endpoint_ format_ format_template_ width_ ecs_extra_ direction_ device_id_);

sub new {
	my $class = shift;
	my %vals = @_;
	my @args = map{$_."_", $vals{$_}} keys %vals; # add underscore to key 

	# note that we won't check for illegal fields
	# so we can pass any value and allow AUTOLOAD to 
	# check the hash for it.
	
	my $self = bless {@args}, $class;

	my $direction = $self->direction; # input or output

	# join IO objects to graph
	my $name;
	try{ $name  = $self->name }
	catch {  say "name method blew up for this object"  }; 

	{ no warnings 'uninitialized';
	Audio::Nama::logit(__LINE__,"Audio::Nama::IO","debug","I belong to track $name\n",
		sub{Dumper($self)} );
	}
	
	if($name){
		$by_name{$name}->{$direction} = $self;
	}
	else {say "DOES NOT HAVE ASSOCIATED TRACK"}
	$self
}

# latency stubs
sub capture_latency { die "capture stub" }
sub playback_latency { die "playback stub" }
sub ports { die "ports stub" }

sub ecs_string {
	my $self = shift;
	my @parts;
	push @parts, '-f:'.$self->format if $self->format;
	push @parts, '-'.$self->io_prefix.':'.$self->device_id;
	join ' ',@parts;
}

## the format() method generates the correct Ecasound format string,
## (e.g. -f:f32_le,2,48000) if the _format_template() method
## returns a signal format template (e.g. f32_le,N,48000)

sub format { 
	my $self = shift;
	Audio::Nama::signal_format($self->format_template, $self->width)
		if $self->format_template and $self->width
}
sub _format_template {} # the leading underscore allows override
                        # by a method without the underscore

sub _ecs_extra {}		# allow override
sub direction { 
	(ref $_[0]) =~ /::from/ ? 'input' : 'output'  
}
sub io_prefix { substr $_[0]->direction, 0, 1 } # 'i' or 'o'

sub AUTOLOAD {
	my $self = shift;
	# get tail of method call
	my ($call) = $AUTOLOAD =~ /([^:]+)$/;
	my $result = q();
	my $field = "$call\_";
	my $method = "_$call";
	return $self->{$field} if exists $self->{$field};
	return $self->$method if $self->can($method);
	{ no warnings 'uninitialized'; 
	if ( my $track = $tn{$self->{track_}} ){
		return $track->$call if $track->can($call) 
		# ->can is reliable here because Track has no AUTOLOAD
	}
	}
	print $self->dump;
	croak "Autoload fell through. Object type: ", (ref $self), ", illegal method call: $call\n";
}

sub DESTROY {}


# The following methods were moved here from the Track class
# because they are only used in generating chain setups.
# They retain $track as the $self variable.

sub _mono_to_stereo{

	# Truth table

	#REC status, Track width stereo: null
	#REC status, Track width mono:   chcopy
	#MON status, WAV width mono:   chcopy
	#MON status, WAV width stereo: null
	#Higher channel count (WAV or Track): null

	my $self   = shift;
	my $status = $self->rec_status();
	my $copy   = "-chcopy:1,2";
	my $nocopy = "";
	my $is_mono_track = sub { $self->width == 1 };
	my $is_mono_wav   = sub { Audio::Nama::channels($self->wav_format) == 1};
	if  (      $status eq 'REC' and $is_mono_track->()
			or $status eq 'MON' and $is_mono_wav->() )
		 { $copy }
	else { $nocopy }
}
sub _playat_output {
	my $track = shift;
	return unless $track->adjusted_playat_time;
		# or $track->latency_offset;
	join ',',"playat" , $track->adjusted_playat_time 
		# + $track->latency_offset
}
sub _select_output {
	my $track = shift;
	no warnings 'uninitialized';
	my $start = $track->adjusted_region_start_time + $config->hardware_latency();
	my $end   = $track->adjusted_region_end_time;
	return unless $config->hardware_latency() or defined $start and defined $end;
	my $setup_length;
	# CASE 1: a region is defined 
	if ($end) { 
		$setup_length = $end - $start;
	}
	# CASE 2: only hardware latency
	else {
		$setup_length = $track->wav_length - $start
	}
	join ',',"select", $start, $setup_length
}
###  utility subroutines

sub get_class {
	my ($type,$direction) = @_;
	Audio::Nama::Graph::is_a_loop($type) and 
		return $io_class{ $direction eq 'input' ?  "loop_source" : "loop_sink"};
	$io_class{$type} or croak "unrecognized IO type: $type"
}
sub soundcard_input_type_string {
	$jack->{jackd_running} ? 'jack_multi_in' : 'soundcard_device_in'
}
sub soundcard_output_type_string {
	$jack->{jackd_running} ? 'jack_multi_out' : 'soundcard_device_out'
}
sub soundcard_input_device_string {
	$jack->{jackd_running} ? 'system' : $config->{alsa_capture_device}
}
sub soundcard_output_device_string {
	$jack->{jackd_running} ? 'system' : $config->{alsa_playback_device}
}

sub jack_multi_route {
	my (@ports)  = @_;
	join q(,),q(jack_multi),
	map{quote_jack_port($_)} @ports
}

sub jack_multi_ports {
	my ($client, $direction, $start, $width, $trackname)  = @_;
	#say "client $client, $direction $direction, start: $start, width $width";
	# can we route to these channels?
	my $end   = $start + $width - 1;

	# the following logic avoids deferencing undef for a 
	# non-existent client, and correctly handles
	# the case of a portname (containing colon)
	
 	my $max = scalar @{$jack->{clients}->{$client}{$direction}};
 	die qq(track $trackname: JACK client "$client", direction: $direction channel ($end) is out of bounds. $max channels maximum.\n) if $end > $max
		and $config->{enforce_channel_bounds};

		return @{$jack->{clients}->{$client}{$direction}}[$start-1..$end-1]
		 	if $jack->{clients}->{$client}{$direction};

}
#sub one_port { $jack->{clients}->{$client}->{$direction}->[$start-1] }
sub default_jack_ports_list {
	my ($track_name) = shift;
	"$track_name.ports"
}
sub quote_jack_port {
	my $port = shift;
	($port =~ /\s/ and $port !~ /^"/) ? qq("$port") : $port
}


### subclass definitions

### method names with a preceding underscore 
### can be overridded by the object constructor

{
package Audio::Nama::IO::from_null;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
sub _device_id { 'null' } # 
}

{
package Audio::Nama::IO::to_null;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
sub _device_id { 'null' }  # underscore for testing
}

{
package Audio::Nama::IO::from_rtnull;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
sub _device_id { 'rtnull' } # 
}

{
package Audio::Nama::IO::to_rtnull;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
sub _device_id { 'rtnull' }  # underscore for testing
}

{
package Audio::Nama::IO::from_wav;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
sub device_id { 
	my $self = shift;
	my @modifiers;
	push @modifiers, $self->playat_output if $self->playat_output;
	push @modifiers, $self->select_output if $self->select_output;
	push @modifiers, split " ", $self->modifiers if $self->modifiers;
	push @modifiers, $self->full_path;
	join(q[,],@modifiers);
}
sub ecs_extra { $_[0]->mono_to_stereo}
}

{
package Audio::Nama::IO::to_wav;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
sub device_id { $_[0]->full_path }
sub _format_template { $config->{raw_to_disk_format} } 
}

{
package Audio::Nama::IO::from_loop;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
sub new {
	my $class = shift;
	my %vals = @_;
	$class->SUPER::new( %vals, device_id => "loop,$vals{endpoint}");
}
}
{
package Audio::Nama::IO::to_loop;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO::from_loop';
}

{
package Audio::Nama::IO::from_soundcard;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
sub new {
	shift; # throw away class
	my $class = $io_class{Audio::Nama::IO::soundcard_input_type_string()};
	$class->new(@_);
}
}
{
package Audio::Nama::IO::to_soundcard;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
sub new {
	shift; # throw away class
	my $class = $io_class{Audio::Nama::IO::soundcard_output_type_string()};
	$class->new(@_);
}
}
{
package Audio::Nama::IO::to_jack_multi;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
sub client {
	my $self = shift;
	my $client = $self->direction eq 'input' 
		? $self->source_id
		: $self->send_id;
}
sub device_id { 
	my $self = shift;
	Audio::Nama::IO::jack_multi_route($self->ports)
}
sub ports {
	my $self = shift;
	# maybe source_id is an input number
	my $client = $self->client;
	my $channel = 1;
	# we want the direction with respect to the client, i.e.  # reversed
	my $client_direction = $self->direction eq 'input' ? 'output' : 'input';
	if( Audio::Nama::dest_type($client) eq 'soundcard'){
		$channel = $client;
		$client = Audio::Nama::IO::soundcard_input_device_string(); # system, okay for output
	}
	Audio::Nama::IO::jack_multi_ports($client,$client_direction,$channel,$self->width, Audio::Nama::try{$self->name} );
}

sub capture_latency {
	my $self = shift;
	my @names = $self->ports();
	#say "found ports: @names";
	Audio::Nama::jack_client_node_latency($names[0], 'input');
}
sub playback_latency {
	my $self = shift;
	my @names = $self->ports();
	#say "found ports: @names";
	Audio::Nama::jack_client_node_latency($names[0], 'input');
}

}

{
package Audio::Nama::IO::from_jack_multi;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO::to_jack_multi';
sub ecs_extra { $_[0]->mono_to_stereo }
}

{
package Audio::Nama::IO::to_jack_port;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
sub format_template { $config->{devices}->{jack}->{signal_format} }
sub device_id { 'jack,,'.$_[0]->port_name.'_out' }
}

{
package Audio::Nama::IO::from_jack_port;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO::to_jack_port';
sub device_id { 'jack,,'.$_[0]->port_name.'_in' }
sub ecs_extra { $_[0]->mono_to_stereo }
}

{
package Audio::Nama::IO::to_jack_client;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
sub device_id { "jack," . Audio::Nama::IO::quote_jack_port($_[0]->send_id); }
}

{
package Audio::Nama::IO::from_jack_client;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
sub device_id { 'jack,'.  Audio::Nama::IO::quote_jack_port($_[0]->source_id); }
sub ecs_extra { $_[0]->mono_to_stereo}
}

{
package Audio::Nama::IO::from_soundcard_device;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
sub ecs_extra { join ' ', $_[0]->rec_route, $_[0]->mono_to_stereo }
sub device_id { $config->{devices}->{$config->{alsa_capture_device}}->{ecasound_id} }
sub input_channel { $_[0]->source_id }
sub rec_route {
	# works for mono/stereo only!
	no warnings qw(uninitialized);
	my $self = shift;
	# needed only if input channel is greater than 1
	return '' if ! $self->input_channel or $self->input_channel == 1; 
	
	my $route = "-chmove:" . $self->input_channel . ",1"; 
	if ( $self->width == 2){
		$route .= " -chmove:" . ($self->input_channel + 1) . ",2";
	}
	return $route;
}
}
{
package Audio::Nama::IO::to_soundcard_device;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
sub device_id { $config->{devices}->{$config->{alsa_playback_device}}{ecasound_id} }
sub ecs_extra {route($_[0]->width,$_[0]->output_channel) }
sub output_channel { $_[0]->send_id }
sub route2 {
	my ($from, $to, $width) = @_;
}
sub route {
	# routes signals (1..$width) to ($dest..$dest+$width-1 )
	
	my ($width, $dest) = @_;
	return '' if ! $dest or $dest == 1;
	# print "route: width: $width, destination: $dest\n\n";
	my $offset = $dest - 1;
	my $route ;
	for my $c ( map{$width - $_ + 1} 1..$width ) {
		$route .= " -chmove:$c," . ( $c + $offset);
	}
	$route;
}
}
{
package Audio::Nama::IO::any;
use Modern::Perl; use vars qw(@ISA); @ISA = 'Audio::Nama::IO';
}


1;
__END__