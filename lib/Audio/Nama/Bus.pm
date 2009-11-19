
# ------------  Bus --------------------

package Audio::Nama::Bus;
use Modern::Perl;
use Carp;
our $VERSION = 1.0;
our ($debug); # entire file
use vars qw(%by_name);
our @ISA;
use Audio::Nama::Object qw(						
					name
					groups
					tracks 
					rules
					destination_type
					destination_id
					bus_type
					class

						);

sub initialize { %by_name = () };
sub new {
	my $class = shift;
	my %vals = @_;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	if (! $vals{name} or $by_name{$vals{name}}){
		carp($vals{name},": missing or duplicate bus name. Skipping.\n");
		return;
	}
	my $bus = bless { 
		tracks => [], 
		groups => [], 
		rules  => [],
		class => $class,
		@_ }, $vals{class} // $class;
	$by_name{$bus->name} = $bus;
}


		
sub apply {
	
	#print join " ", map{ ref $_ } values %Audio::Nama::Rule::by_name; exit;
	my $bus = shift;
	$debug and print q(applying rules for bus "), $bus->name, qq("\n);
	$debug and print "bus name: ", $bus->name, $/;
	$debug and print "groups: ", join " ", @{$bus->groups}, $/;
	$debug and print "rules: ", join " ", @{$bus->rules}, $/;

	# get track names corresponding to this bus
	
	my @track_names = (@{$bus->tracks}, 

		map{ $debug and print "group name: $_\n";
			$debug and print join " ", "keys:", keys( %Audio::Nama::Group::by_name), $/;
			my $group = $Audio::Nama::Group::by_name{$_}; 
			$debug and print "group validated: ", $group->name, $/;
			$debug and print "includes: ", $group->tracks, $/;
			$group->tracks 
								}  @{ $bus->groups }

	);
	$debug and print "tracks: ", join " ", @track_names, $/;
	my @tracks = map{ $Audio::Nama::Track::by_name{$_} } @track_names; 

	map{ my $track = $_; # 
		my $n = $track->n;
		$debug and print "track ", $track->name, " index: $n\n";

		map{ my $rule_name = $_;
			$debug and print "apply rule name: $rule_name\n"; 
			my $rule = $Audio::Nama::Rule::by_name{$_};
			$debug and print "rule $rule"; 
			my $condition_met = deref_code($rule->condition, $track);

		if ($condition_met){
			#print "rule is type: ", ref $rule, $/;
			$debug and print "condition: ", $rule->condition, $/;

			my $key1 = deref_code($rule->input_type, $track);
			my $key2 = deref_code($rule->input_object, $track) ;
			my $chain_id = deref_code($rule->chain_id, $track) ;
			my $rec_status = $track->rec_status;

			$debug and print "chain_id: $chain_id, rec_status: $rec_status, condition: $condition_met,  input key1: $key1, key2: $key2\n";
			if ( 
				$track->rec_status ne 'OFF' 
					and $rule->status
					and ( 		$rule->target =~ /all|none/
							or  $rule->target eq $track->rec_status)
					and $condition_met
						
						)  {

				defined $rule->input_type and
					push @{ $Audio::Nama::inputs{ $key1 }->{ $key2 } }, $chain_id ;

				$key1 = deref_code($rule->output_type, $track);
				$key2 = deref_code($rule->output_object, $track) ;
			$debug and print "chain_id: $chain_id, rec_status: $rec_status, condition: $condition_met, output key1: $key1, key2: $key2\n";

				defined $rule->output_type and
					push @{ $Audio::Nama::outputs{ $key1 }->{ $key2 } }, $chain_id;
			# add intermediate processing
		
		my ($post_input, $pre_output);
		$post_input = deref_code($rule->post_input, $track) 
			if defined $rule->post_input;
		$pre_output = deref_code($rule->pre_output, $track) 
			if defined $rule->pre_output;
		$debug and print "pre_output: $pre_output, post_input: $post_input\n";
		$Audio::Nama::post_input{$chain_id} .= $post_input if defined $post_input;
		$Audio::Nama::pre_output{$chain_id} .= $pre_output if defined $pre_output;
			}
		}

		} @{ $bus->rules } ;
	} @tracks; 
}
# the following is utility code, not an object method

sub deref_code {
	my ($value, $track) = @_;
	my $type = ref $value || "scalar";
	my $tracktype = ref $track;
	#print "found type: $type, value: $value\n";
	#print "found field type: $type, track: ",$track->name, $/;
	if ( $type  =~ /CODE/){
		 $debug and print "code found\n";
		$value = &$value($track);
		 $debug and print "code value: $value\n";
		 $value;
	} else {
		$debug and print "scalar value: $value\n"; 
		$value }
}
sub all { values %by_name };

sub remove { say $_[0]->name, " is system bus, no can remove" }

# we will put the following information in the Track as an aux_send
# 						destination_type
# 						destination_id
# name, init capital e.g. Brass, identical Group name
# destination: 3, jconv, loop,output


package Audio::Nama::SubBus;
use Modern::Perl;
use Carp;
our @ISA = 'Audio::Nama::Bus';

use Audio::Nama::Object qw(
					name
					groups
					tracks 
					rules
					destination_type
					destination_id
					bus_type
					class

);
sub remove {
	my $bus = shift;

	# all tracks returned to Main group
	map{$Audio::Nama::tn{$_}->set(group => 'Main') } $Audio::Nama::Group::by_name{$bus->name}->tracks;

	# remove bus mix track
	$Audio::Nama::tn{$bus->name}->remove;

	# delete group
	$Audio::Nama::Group::by_name{$bus->name}->remove;

	# remove bus
	delete $Audio::Nama::Bus::by_name{$bus->name};
} 

package Audio::Nama::SendBusRaw;
use Modern::Perl;
use Carp;
our @ISA = 'Audio::Nama::Bus';
use Audio::Nama::Object qw(
					name
					groups
					tracks 
					rules
					destination_type
					destination_id
					bus_type
					class


);
sub remove {
	my $bus = shift;

	# delete all (slave) tracks
	map{$Audio::Nama::tn{$_}->remove } $Audio::Nama::Group::by_name{$bus->name}->tracks;

	# delete group
	$Audio::Nama::Group::by_name{$bus->name}->remove;

	# remove bus
	delete $Audio::Nama::Bus::by_name{$bus->name};
}
package Audio::Nama::SendBusCooked;
use Modern::Perl;
use Carp;
our @ISA = 'Audio::Nama::SendBusRaw';
use Audio::Nama::Object qw(
					name
					groups
					tracks 
					rules
					destination_type
					destination_id
					bus_type
					class

);



# ------------  Rule  --------------------
	
package Audio::Nama::Rule;
use Carp;
use vars qw($n %by_name @by_index %rule_names);
$n = 0;
@by_index = ();	# return ref to Track by numeric key
%by_name = ();	# return ref to Track by name
%rule_names = (); 
use Audio::Nama::Object qw( 	name
						chain_id

						target 
					 	condition		

						output_type
						output_object
						output_format

						input_type
						input_object

						post_input
						pre_output 

						status ); # 1 or 0

# chain_id, depends_on, apply_inputs and apply_outputs are
# code refs.
						
#target: REC | MON | chain_id | all | none

sub new {
	# returns a reference to an object that is indexed by
	# name and by an assigned index
	#
	# The indexing is bypassed and an object returned 
	# if an index n is supplied as  a parameter
	
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	croak "rule name already in use: $vals{name}\n"
		 if $rule_names{$vals{name}}; # null name returns false
	$n++;
	my $object = bless { 	
		name 	=> "Rule $n", # default name
		target  => 'all',     # default target
		condition => 1, 	# apply by default
					@_,  			}, $class;

	$rule_names{$vals{name}}++;
	#print "previous rule count: ", scalar @by_index, $/;
	#print "n: $n, name: ", $object->name, $/;
	$by_index[$n] = $object;
	$by_name{ $object->name } = $object;
	$object;
	
}

sub all_rules { @by_index[1..scalar @by_index - 1] }

sub dump{
	my $rule = shift;
	print "rule: ", $rule->name, $/;
}

1;
__END__
