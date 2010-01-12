package Audio::Nama::Group;
use Modern::Perl;
no warnings qw(uninitialized redefine);
our $VERSION = 1.0;
#use Exporter qw(import);
#our @EXPORT_OK =qw(group);
use Carp;
our(%by_name, $debug);
*debug = \$Audio::Nama::debug;
our @ISA;
initialize();

use Audio::Nama::Object qw( 	name
					rw
					version 
					n	
					);

sub initialize {
	%by_name = ();
}

sub new {

	# returns a reference to an object that is indexed by
	# name and by an assigned index
	#
	
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	croak "name missing" unless $vals{name};
	#(carp "group name already in use: $vals{name}\n"), 
		return ($by_name{$vals{name}}) if $by_name{$vals{name}};
	my $object = bless { 	
		rw   	=> 'REC', 
		@_ 			}, $class;
	$by_name{ $object->name } = $object;
	$object;
}


sub tracks { # returns list of track names in group 
	my $group = shift;
	map{ $_->name } grep{ $_->group eq $group->name } Audio::Nama::Track::all();
}

sub last {
	$debug and say "group: @_";
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


sub all { values %by_name }

sub remove {
	my $group = shift;
	delete $by_name{$group->name};
}
		
1;
__END__