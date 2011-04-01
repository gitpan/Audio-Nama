
# ----------- Mark ------------
package Audio::Nama::Mark;
our $VERSION = 1.0;
use Carp;
use warnings;
no warnings qw(uninitialized);
our @ISA;
use vars qw($n %by_name @all);
use Audio::Nama::Object qw( 
				 name 
                 time
				 active
				 );

sub initialize {
	map{ $_->remove} Audio::Nama::Mark::all();
	@all = ();	
	%by_name = ();	# return ref to Mark by name
	@Audio::Nama::marks_data = (); # for save/restore
}
sub new {
	my $class = shift;	
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;

	# to support set_edit_points, we now allow marks to be overwritten
	#
	#croak  "name already in use: $vals{name}\n"
	#	 if $by_name{$vals{name}}; # null name returns false
	
	my $object = bless { 

		## 		defaults ##

					active  => 1,
					name => "",

					@_ 			}, $class;

	#print "object class: $class, object type: ", ref $object, $/;
	if ($object->name) {
		$by_name{ $object->name } = $object;
	}
	push @all, $object;
	$Audio::Nama::this_mark = $object;
	
	$object;
	
}

sub set_name {
	my $mark = shift;
	my $name = shift;
	print "name: $name\n";
	if ( defined $by_name{ $name } ){
	carp "you attempted to assign to name already in use\n";
	}
	else {
		$mark->set(name => $name);
		$by_name{ $name } = $mark;
	}
}

sub jump_here {
	my $mark = shift;
	Audio::Nama::eval_iam( "setpos " . $mark->time);
	$Audio::Nama::this_mark = $mark;
}
sub adjusted_time {  # for marks within current edit
	my $mark = shift;
	return $mark->time unless $Audio::Nama::offset_run_flag;
	my $time = $mark->time - Audio::Nama::play_start_time();
	$time > 0 ? $time : 0
}
sub remove {
	my $mark = shift;
	if ( $mark->name ) {
		delete $by_name{$mark->name};
	}
	$Audio::Nama::debug and warn "marks found: ",scalar @all, $/;
	# @all = (), return if scalar @all
	@all = grep { $_->time != $mark->time } @all;

}
sub next { 
	my $mark = shift;
	Audio::Nama::next_mark();
}
sub previous {
	my $mark = shift; 
	Audio::Nama::previous_mark();
}

# -- Class Methods

sub all { sort { $a->{time} <=> $b->{time} }@all }

sub loop_start { 
	my @points = sort { $a <=> $b } 
	grep{ $_ } map{ mark_time($_)} @Audio::Nama::loop_endpoints[0,1];
	#print "points @points\n";
	$points[0];
}
sub loop_end {
	my @points =sort { $a <=> $b } 
		grep{ $_ } map{ mark_time($_)} @Audio::Nama::loop_endpoints[0,1];
	$points[1];
}
sub unadjusted_mark_time {
	my $tag = shift;
	$tag or $tag = '';
	#print "tag: $tag\n";
	my $mark;
	if ($tag =~ /\./) { # we assume raw time if decimal
		#print "mark time: ", $tag, $/;
		return $tag;
	} elsif ($tag =~ /^\d+$/){
		#print "mark index found\n";
		$mark = $Audio::Nama::Mark::all[$tag];
	} else {
		#print "mark name found\n";
		$mark = $Audio::Nama::Mark::by_name{$tag};
	}
	return undef if ! defined $mark;
	#print "mark time: ", $mark->time, $/;
	return $mark->time;
}
sub mark_time {
	my $tag = shift;
	my $time = unadjusted_mark_time($tag);
	return unless defined $time;
	$time -= Audio::Nama::play_start_time() if Audio::Nama::edit_mode();
	$time
}
	
1;