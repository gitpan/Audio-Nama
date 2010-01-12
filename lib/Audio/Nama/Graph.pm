package Audio::Nama::Graph;
use Modern::Perl;
use Carp;
use Graph;
use vars qw(%reserved $debug $debug2);
# this dispatch table also identifies labels reserved
# for signal sources and sinks.
*reserved = \%Audio::Nama::IO::io_class;
*debug = \$Audio::Nama::debug;
*debug2 = \$Audio::Nama::debug2;

my %seen;

sub expand_graph {
	
	my $g = shift; 
	%seen = ();
	
	
	for ($g->edges){
		my($a,$b) = @{$_}; 
		$debug and say "$a-$b: processing...";
		$debug and say "$a-$b: already seen" if $seen{"$a-$b"};
		next if $seen{"$a-$b"};

		# case 1: both nodes are tracks: default insertion logic
	
		if ( is_a_track($a) and is_a_track($b) ){ 
			$debug and say "processing track-track edge: $a-$b";
			add_loop($g,$a,$b) } 

		# case 2: fan out from track: use near side loop

		elsif ( is_a_track($a) and $g->successors($a) > 1 ) {
			$debug and say "fan_out from track $a";
			add_near_side_loop($g,$a,$b,out_loop($a));}
	
		# case 3: fan in to track: use far side loop
		
		elsif ( is_a_track($b) and $g->predecessors($b) > 1 ) {
			$debug and say "fan in to track $b";
			add_far_side_loop($g,$a,$b,in_loop($b));}
		else { $debug and say "$a-$b: no action taken" }
	}
	
}
sub add_path {
	my @nodes = @_;
	$debug and say "adding path: ", join " ", @nodes;
	$Audio::Nama::g->add_path(@nodes);
}
sub add_edge { add_path(@_) }
	
sub add_inserts {
	my $g = shift;
	my @track_names = grep{ $Audio::Nama::tn{$_} 
		and $Audio::Nama::tn{$_}->group ne 'Temp'
		and $Audio::Nama::tn{$_}->inserts =~ /HASH/
		and $Audio::Nama::tn{$_}->inserts->{insert_type}} $g->vertices;
	$debug and say "Inserts will be applied to the following tracks: @track_names";
	map{ add_insert($g, $_) } @track_names;
}
	
sub add_insert {

	# Inserts will be read-only objects. To change the 
	# destination or return, users will remove the insert and
	# create a new one.
	#
	# Since this routine will be called after expand_graph, 
	# we can be sure that every track will connect to either 
	# a loop or an output 
	#
	# we can add the wet/dry tracks on every generate_setup() run
	# since the Track class will return us the existing
	# track if we use the same name
	#
	no warnings qw(uninitialized);

	my ($g, $name) = @_;
	$debug and say "add_insert for track: $name";
	my $t = $Audio::Nama::tn{$name}; 
	my $i = $t->inserts;  # only one allowed

	say "insert structure:", Audio::Nama::yaml_out($i);
	# assume post-fader send
	# t's successor will be loop or reserved

	# case 1: post-fader insert
		
	if($i->{insert_type} eq 'cooked') {	 # the only type we support
	
		my ($successor) = $g->successors($name);
		$g->delete_edge($name, $successor);
		my $loop = "$name\_insert";
		my $wet = $Audio::Nama::tn{"$name\_wet"};
		my $dry = $Audio::Nama::tn{"$name\_dry"};

		say "found wet: ", $wet->name, " dry: ",$dry->name;

		# wet send path (no track): track -> loop -> output
		
		my @edge = ($loop, Audio::Nama::output_node($i->{send_type}));
		say "edge: @edge";
		add_path($name, @edge);
		$g->set_vertex_attributes($loop, {n => $t->n, j => 'a'});
		$g->set_edge_attributes(@edge, { 
			send_id => $i->{send_id},
			width => 2,
		});
		# wet return path: input -> wet_track (slave) -> successor
		
		# we override the input with the insert's return source

		$g->set_vertex_attributes($wet->name, {
					width => 2, # default for cooked
					mono_to_stereo => '', # override
					source_type => $i->{return_type},
					source_id => $i->{return_id},
		});
		add_path(Audio::Nama::input_node($i->{return_type}), $wet->name, $successor);

		# connect dry track to graph
		
		add_path($loop, $dry->name, $successor);

		Audio::Nama::command_process($t->name); 
		Audio::Nama::command_process('wet '.$i->{wetness});
		# generate_setup() will reset current track 
	}
	
}
	

sub add_loop {
	my ($g,$a,$b) = @_;
	$debug and say "adding loop";
	my $fan_out = $g->successors($a);
	$debug and say "$a: fan_out $fan_out";
	my $fan_in  = $g->predecessors($b);
	$debug and say "$b: fan_in $fan_in";
	if ($fan_out > 1){
		add_near_side_loop($g,$a,$b, out_loop($a))
	} elsif ($fan_in  > 1){
		add_far_side_loop($g,$a,$b, in_loop($b))
	} elsif ($fan_in == 1 and $fan_out == 1){

	# we expect a single user track to feed to Master_in 
	# as multiple user tracks do
	
			$b eq 'Master' 
				?  add_far_side_loop($g,$a,$b,in_loop($b))

	# otherwise default to near_side ( *_out ) loops
				: add_near_side_loop($g,$a,$b,out_loop($a));

	} else {croak "unexpected fan"};
}

 sub add_near_side_loop {

# a - b
# a - c
# a - d
#
# converts to 
#
# a_out - b
# a_out - c
# a_out - d
# a - a_out

# we deal with all edges departing from $a, the left node.
# I call it a-x below, but it is actually a-$_ where $_ 
# is an alias to each of the successor node.
#
# 1. start with a - x
# 
# 2. delete a - x 
# 
# 3. add a - a_out
# 
# 4. add a_out - x
# 
# 5. Add a_out attributes for track name and 
#    other info need to generate correct chain_ids
#
# 6. Copy any attributes of edge a - x  to a_out - x.
#
#  No multiedge handling needed because with our 
#  current topology, we never have a track
#  with, for example, multiple edges to a soundcard.
#
#  Send buses create new tracks to provide connections.
#
# I will be moving edges (along with their attributes)
# but I cannot assign chain_id them because I have
# no way of knowing which is the edge that will use
# the track number and will therefore get the track effects

 	my ($g, $a, $b, $loop) = @_;
 	$debug and say "$a-$b: insert near side loop";
	# we will insert loop _after_ processing successor
	# edges so $a-$loop will not be picked up 
	# in successors list.
	
	# We will assign chain_ids to loop-to-loop edges
	# looking like J7a, J7b,...
	#
	# To make this possible, we store the following 
	# information in the left vertex of
	# the edge:
	#
	# n: track index, j: alphabetical counter
	 
	$g->set_vertex_attributes($loop,{
		n => $Audio::Nama::tn{$a}->n, j => 'a',
		track => $Audio::Nama::tn{$a}->name});
	map{ 
 		my $attr = $g->get_edge_attributes($a,$_);
 		$debug and say "deleting edge: $a-$_";
 		$g->delete_edge($a,$_);
 		$debug and say "adding edge: $loop-$_";
		add_edge($loop, $_);
		$g->set_edge_attributes($loop,$_, $attr) if $attr;
		$seen{"$a-$_"}++;
 	} $g->successors($a);
	$debug and say "adding edge: $a-$loop";
	add_edge($a,$loop);
}
 

sub add_far_side_loop {
 	my ($g, $a, $b, $loop) = @_;
 	$debug and say "$a-$b: insert far side loop";
	
	$g->set_vertex_attributes($loop,{
		n => $Audio::Nama::tn{$a}->n, j => 'a',
		track => $Audio::Nama::tn{$a}->name});
	map{ 
 		my $attr = $g->get_edge_attributes($_,$b);
 		$debug and say "deleting edge: $_-$b";
 		$g->delete_edge($_,$b);
 		$debug and say "adding edge: $_-$loop";
		add_edge($_,$loop);
		$g->set_edge_attributes($_,$loop, $attr) if $attr;
		$seen{"$_-$b"}++;
 	} $g->predecessors($b);
	$debug and say "adding edge: $loop-$b";
	add_edge($loop,$b);
}


sub in_loop{ "$_[0]_in" }
sub out_loop{ "$_[0]_out" }
#sub is_a_track{ $Audio::Nama::tn{$_[0]} }
sub is_a_track{ return unless $_[0] !~ /_(in|out)$/;}
# $debug and say "$_[0] is a track"; 1
#}
sub is_terminal { $reserved{$_[0]} }
sub is_a_loop{
	my $name = shift;
	return if $reserved{$name};
	if (my($root, $suffix) = $name =~ /^(.+?)_(in|out|insert)$/){
		return ($root, $suffix);
	} 
}
sub is_a_jumper { 		! is_terminal($_[0])
				 	and ! is_a_track($_[0]) 
					and ! is_a_loop($_[0]) }
	

sub inputless_tracks {
	my $g = shift;
	(grep{ is_a_track($_) and $g->is_source_vertex($_) } $g->vertices)
}	
sub remove_inputless_tracks {
	my $g = shift;
	while(my @i = Audio::Nama::Graph::inputless_tracks($g)){
		map{ 	$g->delete_edges(map{@$_} $g->edges_from($_));
				$g->delete_vertex($_);
		} @i;
	}
}
sub outputless_tracks {
	my $g = shift;
	(grep{ is_a_track($_) and $g->is_sink_vertex($_) } $g->vertices)
}	
sub remove_outputless_tracks {
	my $g = shift;
	while(my @i = Audio::Nama::Graph::outputless_tracks($g)){
		map{ 	$g->delete_edges(map{@$_} $g->edges_to($_));
				$g->delete_vertex($_);
		} @i;
	}
}
		
1;
__END__

The graphic routing system is complicated enough that some comment is
warranted.

The first step of routing is to create a graph that expresses the signal flow.

	soundcard_in -> sax -> Master -> soundcard_out

If we are to record the input, we need:

	sax -> wav_out

If we add an instrument monitor for the sax player, we need:

	sax -> soundcard_out

Ecasound requires that we insert loop devices wherever the signals
must fan out or fan in.

	soundcard_in -> sax -> sax_out -> Master -> soundcard_out

	sax_out -> wav_out

	sax_out -> soundcard_out

Here 'sax_out' is a loop device.

Though there are more complicated additions, such as inserts,
they must follow these same rules.

We then process each edge to generate a line for the Ecasound chain setup
file.

Master -> soundcard_out is easy to process, because the track
Master knows what it's outputs should be.

The edge sax_out -> soundcard_out, an auxiliary send, needs to know its
associated track, as well as the chain_id, the identifier for the Ecasound
chain corresponding to this edge.

We provide this information as edge attributes.

We also allow vertexes, for example a track or loop device, to carry data is
well, for example to tell the dispatcher to override the 
chain_id of a temporary track.

An Ecasound chain setup is a graph comprised of multiple 
signal processing chains, each of which consists 
of exactly one input and one output.
 
The dispatch process transforms the graph edges into a group of 
IO objects, each with enough information to create
the input or output fragment of a chain.

Finally, these objects are processed into the Ecasound
chain setup file. 