package Audio::Nama::Object;
use Modern::Perl;
use Carp;
use Audio::Nama::Assign qw(yaml_out); 

no strict; # Enable during dev and testing
BEGIN {
	require 5.004;
	$Audio::Nama::Object::VERSION = '1.04';
}

sub import {
	return unless shift eq 'Audio::Nama::Object';
	my $pkg   = caller;
	my $child = !! @{"${pkg}::ISA"};
	eval join '',
		"package $pkg;\n",
		' use vars qw(%_is_field);   ',
		' map{ $_is_field{$_}++ } @_;',
		($child ? () : "\@${pkg}::ISA = 'Audio::Nama::Object';\n"),
		map {
			defined and ! ref and /^[^\W\d]\w*$/s
			or die "Invalid accessor name '$_'";
			"sub $_ { return \$_[0]->{$_} }\n"
		} @_;
	die "Failed to generate $pkg" if $@;
	return 1;
}

sub new {
	my $class = shift;
	bless { @_ }, $class;
}

sub is_legal_key { 
	my ($class, $key) = @_;
	$class = ref $class if ref $class;  # support objects
	return 1 if ${"$class\::_is_field"}{$key};
	my ($parent_class) = @{"$class\::ISA"};
	return unless $parent_class and $parent_class !~ /Object::Tiny/;
	is_legal_key($parent_class,$key);
}
sub set {
	my $self = shift;
	my $class = ref $self;
	#print "class: $class, args: @_\n";
 	croak "odd number of arguments ",join "\n--\n" ,@_ if @_ % 2;
	my %new_vals = @_;
	map{ 
		$self->{$_} = $new_vals{$_} ;
			my $key = $_;
			is_legal_key(ref $self, $key) or croak "illegal key: $_ for object of type ", ref $self;
	} keys %new_vals;
}
# sub ancestors {
# 	my $class = ref $_[0];
# 	$class, parents( @{"$class\::ISA"} );
# }
# 
# sub parents {
# 	my @ISA = @_;
# 	map{ 
sub dumpp  {
	my $self = shift;
	my $class = ref $self;
	bless $self, 'HASH'; # easy magic
	my $output = yaml_out $self;
	print "Object class: $class\n";
	print $output, "\n";
	bless $self, $class; # restore
}
sub dump {
	my $self = shift;
	my $class = ref $self;
	bless $self, 'HASH'; # easy magic
	my $output = yaml_out $self;
	bless $self, $class; # restore
	return $output;
}
sub hashref {
	my $self = shift;
	my $class = ref $self;
	bless $self, 'HASH'; # easy magic
	#print yaml_out $self; return;
	my %guts = %{ $self };
	#print join " ", %guts; return;
	#my @keys = keys %guts;
	#map{ $output->{$_} or $output->{$_} = '~'   } @keys; 
	bless $self, $class; # restore
	return \%guts;
}

1;

__END__

=pod

=head1 NAME

::Object - Class builder

=head1 SYNOPSIS

  # Define a class
  package Foo;
  
  use Audio::Nama::Object qw{ bar baz };
  
  1;
  
  
  # Use the class
  my $object = Foo->new( bar => 1 );

  $object->set( bar => 2);
  
  print "bar is " . $object->bar . "\n";