# ------------- Effect-Chain and -Profile routines --------

package Audio::Nama;
use Modern::Perl;
no warnings 'uninitialized';

our (
	$project_name,
	$this_track,
	%effect_chain,
	%effect_profile,
	$debug,
	$debug2,
	%tn,
	%cops,
	%copp,
	$magical_cop_id,
);


sub private_effect_chain_name {
	my $name = "_$project_name/".$this_track->name.'_';
	my $i;
	map{ my ($j) = /_(\d+)$/; $i = $j if $j > $i; }
	@{ $this_track->effect_chain_stack }, 
		grep{/$name/} keys %effect_chain;
	$name . ++$i
}
sub profile_effect_chain_name {
	my ($profile, $track_name) = @_;
	"_$profile\:$track_name";
}

# too many functions in push and pop!!

sub push_effect_chain {
	$debug2 and say "&push_effect_chain";
	my ($track, %vals) = @_; 

	# use supplied ops list, or default to user-applied (fancy) ops
	
	my @ops = $vals{ops} ? @{$vals{ops}} : $track->fancy_ops;
	say("no effects to store"), return unless @ops;

	# use supplied name, or default to private name that will now show 
	# in listing
	
	my $save_name   = $vals{save} || private_effect_chain_name();
	$debug and say "save name: $save_name"; 

	# create a new effect-chain definition
	
	new_effect_chain( $track, $save_name, @ops ); # current track effects

	# store effect-chain name on track effect-chain stack
	
	push @{ $track->effect_chain_stack }, $save_name;

	# remove stored effects
	
	map{ remove_effect($_)} @ops;

	# return name

	$save_name;
}

sub pop_effect_chain { # restore previous
	$debug2 and say "&pop_effect_chain";
	my $track = shift;
	my $previous = pop @{$track->effect_chain_stack};
	say("no previous effect chain"), return unless $previous;
	map{ remove_effect($_)} $track->fancy_ops;
	add_effect_chain($track, $previous);
	delete $effect_chain{$previous};
}
sub overwrite_effect_chain {
	$debug2 and say "&overwrite_effect_chain";
	my ($track, $name) = @_;
	print("$name: unknown effect chain.\n"), return if !  $effect_chain{$name};
	push_effect_chain($track) if $track->fancy_ops;
	add_effect_chain($track,$name); 
}
sub new_effect_profile {
	$debug2 and say "&new_effect_profile";
	my ($bunch, $profile) = @_;
	my @tracks = bunch_tracks($bunch);
	say qq(effect profile "$profile" created for tracks: @tracks);
	map { new_effect_chain($tn{$_}, profile_effect_chain_name($profile, $_)); 
	} @tracks;
	$effect_profile{$profile}{tracks} = [ @tracks ];
	save_effect_chains();
	save_effect_profiles();
}
sub delete_effect_profile { 
	$debug2 and say "&delete_effect_profile";
	my $name = shift;
	say qq(deleting effect profile: $name);
	my @tracks = $effect_profile{$name};
	delete $effect_profile{$name};
	map{ delete $effect_chain{profile_effect_chain_name($name,$_)} } @tracks;
}

sub apply_effect_profile {  # overwriting current effects
	$debug2 and say "&apply_effect_profile";
	my ($function, $profile) = @_;
	my @tracks = @{ $effect_profile{$profile}{tracks} };
	my @missing = grep{ ! $tn{$_} } @tracks;
	@missing and say(join(',',@missing), ": tracks do not exist. Aborting."),
		return;
	@missing = grep { ! $effect_chain{profile_effect_chain_name($profile,$_)} } @tracks;
	@missing and say(join(',',@missing), ": effect chains do not exist. Aborting."),
		return;
	map{ $function->( $tn{$_}, profile_effect_chain_name($profile,$_)) } @tracks;
}
sub list_effect_profiles { 
	my @results;
	while( my $name = each %effect_profile){
		push @results, "effect profile: $name\n";
		push @results, list_effect_chains("_$name:");
	}
	@results;
}

sub restore_effects { pop_effect_chain($_[0])}

sub new_effect_chain {
	my ($track, $name, @ops) = @_;
#	say "name: $name, ops: @ops";
	@ops or @ops = $track->fancy_ops;
	say $track->name, qq(: creating effect chain "$name") unless $name =~ /^_/;
	$effect_chain{$name} = { 
					ops 	=> \@ops,
					type 	=> { map{$_ => $cops{$_}{type} 	} @ops},
					params	=> { map{$_ => $copp{$_} 		} @ops},
	};
	save_effect_chains();
}

sub add_effect_chain {
	my ($track, $name) = @_;
	#say "track: $track name: ",$track->name, " effect chain: $name";
	say("$name: effect chain does not exist"), return 
		if ! $effect_chain{$name};
	say $track->name, qq(: adding effect chain "$name") unless $name =~ /^_/;
	my $before = $track->vol;
	map {  $magical_cop_id = $_ unless $cops{$_}; # try to reuse cop_id
		if ($before){
			Audio::Nama::Text::t_insert_effect(
				$before, 
				$effect_chain{$name}{type}{$_}, 
				$effect_chain{$name}{params}{$_});
		} else { 
			Audio::Nama::Text::t_add_effect(
				$track, 
				$effect_chain{$name}{type}{$_}, 
				$effect_chain{$name}{params}{$_});
		}
		$magical_cop_id = undef;
	} @{$effect_chain{$name}{ops}};
}	
sub list_effect_chains {
	my @frags = @_; # fragments to match against effect_chain names
    # we don't list chain_ids starting with underscore
    # except when searching for particular chains
    my @ids = grep{ @frags or ! /^_/ } keys %Audio::Nama::effect_chain;
	if (@frags){
		@ids = grep{ my $id = $_; grep{ $id =~ /$_/} @frags} @ids; 
	}
	my @results;
	map{ my $name = $_;
		push @results, join ' ', "$name:", 
		map{$effect_chain{$name}{type}{$_},
			@{$effect_chain{$name}{params}{$_}}
		} @{$effect_chain{$name}{ops}};
		push @results, "\n";
	} @ids;
	@results;
}
1;
__END__