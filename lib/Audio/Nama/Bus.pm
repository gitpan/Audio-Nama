
# ------------  Bus --------------------

package Audio::Nama::Bus;
use Modern::Perl; use Carp; our @ISA;
our $VERSION = 1.0;
our ($debug, %by_name); 
use Audio::Nama::Object qw(
					name
					destinations
					send_type
					send_id
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
		class => $class, # for serialization, may be overridden
		@_ }, $vals{class} // $class; # for restore
	$by_name{$bus->name} = $bus;
}
sub group { $_[0]->name }
sub all { values %by_name };

sub remove { say $_[0]->name, " is system bus. No can remove." }

### subclasses

package Audio::Nama::SubBus;
use Modern::Perl; use Carp; our @ISA = 'Audio::Nama::Bus';

# graphic routing: track -> mix_track

sub apply {
	my $bus = shift;
	return unless $Audio::Nama::tn{$bus->name}->rec_status eq 'REC';
	map{ 
		# connect signal sources to tracks
		my @path = $_->input_path;
		$Audio::Nama::g->add_path(@path) if @path;

		# connect tracks to mix track
		
		$Audio::Nama::g->add_edge($_->name, $bus->name); 

	} grep{ $_->group eq $bus->group} Audio::Nama::Track::all()
}
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
	map{$Audio::Nama::tn{$_}->remove } $Audio::Nama::Group::by_name{$bus->name}->tracks;

	# delete group
	$Audio::Nama::Group::by_name{$bus->name}->remove;

	# remove bus
	delete $Audio::Nama::Bus::by_name{$bus->name};
}
package Audio::Nama::SendBusCooked;
use Modern::Perl; use Carp; our @ISA = 'Audio::Nama::SendBusRaw';

# graphic routing: target -> slave -> bus_send_type

sub apply {
	my $bus = shift;
	map{ my @edge = ($_->name, Audio::Nama::output_node($bus->send_type));
		 $Audio::Nama::g->add_path( $_->target, @edge);
		 $Audio::Nama::g->set_edge_attributes( @edge, { 
				send_id => $bus->send_id,
				width => 2})
	} grep{ $_->group eq $bus->group} Audio::Nama::Track::all()
}

1;
__END__