# ---------- Persistent State Support -------------


package Audio::Nama;
use File::Copy;
use Modern::Perl; no warnings 'uninitialized';

sub git { 
	$config->{use_git} or warn("@_: git command, but git is not enabled.
You may want to set use_git: 1 in .namarc"), return;
	
	logpkg(__FILE__,__LINE__,'debug',"VCS command: git @_"); 
	$project->{repo}->run(@_) }
		
sub save_state {
	my $filename = shift;
	if ($filename)
	{

		# remove extension if present
		
		$filename =~ s/\.json//;

		# append filename if warranted
		
		$filename = 
				$filename =~ m{/} 	
									? $filename	# as-is if input contains slashes
									: join_path(project_dir(),$filename) 
	}
	my $path = $filename || $file->state_store();
	logsub("&save_state");
	$project->{save_file_version_number} = $VERSION;

	# some stuff get saved independently of our state file
	
	logpkg(__FILE__,__LINE__,'debug', "saving palette");
	$ui->save_palette;

	# do nothing more if only Master and Mixdown
	
	if (scalar @Audio::Nama::Track::all == 2 ){
		throw("No user tracks, skipping...");
		return;
	}

	print "\nSaving state as ",
	save_system_state($path), "\n";
	save_global_effect_chains();

	# store alsa settings

	if ( $config->{opts}->{a} ) {
		my $filename = $filename;
		$filename =~ s/\.yml$//;
		print "storing ALSA settings\n";
		print qx(alsactl -f $filename.alsa store);
	}
}
sub initialize_marshalling_arrays {
	@tracks_data = (); # zero based, iterate over these to restore
	@bus_data = (); # 
	@marks_data = ();
	@fade_data = ();
	@inserts_data = ();
	@edit_data = ();
	@project_effect_chain_data = ();
	@global_effect_chain_data = ();
	$text->{command_history} = {};

}

sub save_system_state {

	my $path = shift;
	my $output_format = shift;

	sync_effect_parameters(); # in case a controller has made a change
	# we sync read-only parameters, too, but I think that is
	# harmless

	# remove null keys in $fx->{applied} and $fx->{params}
	# would be better to find where they come from
	
	delete $fx->{applied}->{''};
	delete $fx->{params}->{''};

	initialize_marshalling_arrays();
	
	# prepare tracks for storage
	
	$this_track_name = $this_track->name;

	logpkg(__FILE__,__LINE__,'debug', "copying tracks data");

	map { push @tracks_data, $_->as_hash } Audio::Nama::Track::all();

	# print "found ", scalar @tracks_data, "tracks\n";

	# delete obsolete fields
	map { my $t = $_;
				map{ delete $t->{$_} } 
					qw(ch_r ch_m source_select send_select jack_source jack_send);
	} @tracks_data;


	logpkg(__FILE__,__LINE__,'debug', "copying bus data");

	@bus_data = map{ $_->as_hash } Audio::Nama::Bus::all();

	# prepare inserts data for storage
	
	logpkg(__FILE__,__LINE__,'debug', "copying inserts data");
	
	@inserts_data = map{ $_->as_hash } values %Audio::Nama::Insert::by_index;

	# prepare marks data for storage (new Mark objects)

	logpkg(__FILE__,__LINE__,'debug', "copying marks data");
	@marks_data = map{ $_->as_hash } Audio::Nama::Mark::all();

	@fade_data = map{ $_->as_hash } values %Audio::Nama::Fade::by_index;

	@edit_data = map{ $_->as_hash } values %Audio::Nama::Edit::by_index;

	@project_effect_chain_data = map { $_->as_hash } Audio::Nama::EffectChain::find(project => 1);

	# save history -- 50 entries, maximum

	my @history;
	@history = $text->{term}->GetHistory if $text->{term};
	my %seen;
	$text->{command_history} = [];
	map { push @{$text->{command_history}}, $_ 
			unless $seen{$_}; $seen{$_}++ } @history;
	my $max = scalar @{$text->{command_history}};
	$max = 50 if $max > 50;
	@{$text->{command_history}} = @{$text->{command_history}}[-$max..-1];
	logpkg(__FILE__,__LINE__,'debug', "serializing");

	my @formats = $output_format || $config->serialize_formats;

	map{ 	my $format = $_ ;
			serialize(
				file => $path,
				format => $format,
				vars => \@persistent_vars,
				class => 'Audio::Nama',
				);

	} @formats;

	serialize(
		file => $file->untracked_state_store,
		format => 'json',
		vars => \@persistent_untracked_vars,
		class => 'Audio::Nama',
	);	

	"$path.json";
}
{
my %is_legal_suffix = ( 
		json => 'json', 
		yml => 'yaml', 
		pl 	 => 'perl',
		bin  => 'storable',
		yaml => 'yaml', # we allow formats as well
		perl => 'perl',
		storable => 'storable',
);
sub get_newest {
	
	# choose the newest
	#
	my ($path, $format) = @_;
	
	# simply return the file
	# if filename matches exactly, 
	# and we know the format
	
	return($path, $format) if -f $path and $is_legal_suffix{$format};

	my ($dir, $name) = $path =~ m!^(.*?)([^/]+)$!; 
	
	# otherwise we glob, sort and filter directory entries
	
	my @sorted = 
		sort{ $a->[1] <=> $b->[1] } 
		grep{ $is_legal_suffix{$_->[2]} }
		map 
		{ 
			my ($suffix) = m/^$path(?:\.(\w+))?$/;
			[$_, -M $_, $suffix] 
		} 
		glob("$path*");
	logpkg(__FILE__,__LINE__,'debug', sub{yaml_out \@sorted});
	($sorted[0]->[0], $sorted[0]->[2]);
}
}

{ my %decode = 
	(
		json => \&json_in,
		yaml => sub 
		{ 
			my $yaml = shift;
			# remove empty key hash lines # fixes YAML::Tiny bug
			$yaml = join $/, grep{ ! /^\s*:/ } split $/, $yaml;

			# rewrite obsolete null hash/array substitution
			$yaml =~ s/~NULL_HASH/{}/g;
			$yaml =~ s/~NULL_ARRAY/[]/g;

			# rewrite $fx->{applied} 'owns' field to []
			
			# Note: this should be fixed at initialization
			# however we should leave this code 
			# for compatibility with past projects.
			
			$yaml =~ s/owns: ~/owns: []/g;

			$yaml = quote_yaml_scalars( $yaml );

			yaml_in($yaml);
		},
		perl => sub {my $perl_source = shift; eval $perl_source},
		storable => sub { my $bin = shift; thaw( $bin) },
	);
	
	# allow dispatch by either file format or suffix 
	@decode{qw(yml pl bin)} = @decode{qw(yaml perl storable)};

sub decode {

	my ($source, $suffix) = @_;
	$decode{$suffix} 
		or die qq(key $suffix: expecting one of).join q(,),keys %decode;
	$decode{$suffix}->($source);
}
}

sub git_tag_exists {
	my $tag = shift;
	grep { $tag eq $_ } git( 'tag','--list');
}

sub tag_branch { "$_[0]-branch" }

sub restore_state_from_vcs {
	logsub("&restore_state_from_vcs");
	my $name = shift; # tag or branch
	
	# checkout branch if matching branch exists
	
    if (git_branch_exists($name)){
		pager3( qq($name: branch exists. Checking out branch $name.) );
		git_checkout($name);
		
	}

	# checkout branch diverging at tag if matching that tag

	elsif ( git_tag_exists($name) ){

		my $tag = $name;
		my $branch = tag_branch($tag);
	
		if (git_branch_exists($branch)){
			pager3( qq(tag $tag: matching branch exists. Checking out $branch.) );
			git_checkout($branch);
		}

		else {
			pager3( "Creating and checking out branch $branch from tag $tag");
			git_create_branch($branch, $tag);
			
		}
	}
 	else { throw("$name: tag doesn't exist. Cannot checkout."), return  }

	restore_state_from_file();
}
 
sub restore_state_from_file {
	logsub("&restore_state_from_file");
	my $filename = shift;
	$filename =~ s/\.json$//;
	$filename = join_path(project_dir(), $filename) 
		if $filename and not $filename =~ m(/);
	$filename ||= $file->state_store();

	# get state file, newest if more than one
	# with same name, differing extensions
	# i.e. State.json and State.yml
	initialize_marshalling_arrays();

	my( $path, $suffix ) = get_newest($filename);
	
	logpkg(__FILE__,__LINE__,'debug', "using file: $path");

	throw(
		$path ? "path: == $path.* ==," : "undefined path,"
			," state file not found"), return if ! -f $path;

	my $source = read_file($path);
	my $ref = decode($source, $suffix);
	logpkg(__FILE__,__LINE__,'debug', "suffix: $suffix");	
	logpkg(__FILE__,__LINE__,'debug', "source: $source");

	
	( $path, $suffix ) = get_newest($file->untracked_state_store);
	if ($path)
	{
		$source = read_file($path);

		my $ref = decode($source, $suffix);
		assign(
				data	=> $ref,	
				vars   	=> \@persistent_untracked_vars,
				class 	=> 'Audio::Nama');
		assign_singletons( { data => $ref });
	}
	
	( $path, $suffix ) = get_newest($file->state_store);
	if ($path)
	{
		$source = read_file($path);
		$ref = decode($source, $suffix);

		assign(
					data => $ref,
					vars   => \@persistent_vars,
					class => 'Audio::Nama');
		

		# perform assignments for singleton
		# hash entries (such as $fx->{applied});
		# that that assign() misses
		
		assign_singletons({ data => $ref });

	}
	
	# remove null keyed entry from $fx->{applied},  $fx->{params}

	delete $fx->{applied}->{''};
	delete $fx->{params}->{''};


	my @keys = keys %{$fx->{applied}};

	my @spurious_keys = grep { effect_entry_is_bad($_) } @keys;

	if (@spurious_keys){

		logpkg(__FILE__,__LINE__,'logwarn',"full key list is @keys"); 
		logpkg(__FILE__,__LINE__,'logwarn',"spurious effect keys found @spurious_keys"); 
		logpkg(__FILE__,__LINE__,'logwarn',"deleting them..."); 
		
		map{ 
			delete $fx->{applied}->{$_}; 
			delete $fx->{params}->{$_}  
		} @spurious_keys;

	}

	restore_global_effect_chains();

	
	my @vars = qw(
				@tracks_data
				@bus_data
				@groups_data
				@marks_data
				@fade_data
				@edit_data
				@inserts_data
	);

	# remove non HASH entries
	map {
		my $var = $_;
		my $eval_text  = qq($var  = grep{ ref =~ /HASH/ } $var );
		logpkg(__FILE__,__LINE__,'debug', "want to eval: $eval_text "); 
		eval $eval_text;
	} @vars;


	####### Backward Compatibility ########

	if ( $project->{save_file_version_number} <= 1.100){ 
		map{ Audio::Nama::EffectChain::move_attributes($_) } 
			(@project_effect_chain_data, @global_effect_chain_data)
	}

	#######################################


	#  destroy and recreate all buses

	Audio::Nama::Bus::initialize();	

	create_system_buses(); 

	# restore user buses
		
	# Main exists, therefore is not created, stored values 
	# are lost.  TODO
	
	map{ my $class = $_->{class}; $class->new( %$_ ) } @bus_data;

	# restore user tracks
	
	my $did_apply = 0;

	# temporary turn on mastering mode to enable
	# recreating mastering tracksk

	my $current_master_mode = $mode->{mastering};
	$mode->{mastering} = 1;

	map{ $_->{latency_op} = delete $_->{latency} if $_->{latency} } @tracks_data;
	map{ 
		my %h = %$_; 
		my $class = $h{class} || "Audio::Nama::Track";
		my $track = $class->new( %h );
	} @tracks_data;

	$mode->{mastering} = $current_master_mode;

	# restore inserts
	
	Audio::Nama::Insert::initialize();
	
	map{ 
		bless $_, $_->{class}; # bless directly, bypassing constructor
		$Audio::Nama::Insert::by_index{$_->{n}} = $_;
	} @inserts_data;

	$ui->create_master_and_mix_tracks();

	$this_track = $tn{$this_track_name} if $this_track_name;
	set_current_bus();

	
	map{ 
		my $n = $_->{n};

		# create gui
		$ui->track_gui($n) unless $n <= 2;

		# restore effects
		
		for my $id (@{$ti{$n}->ops}){
			$did_apply++  # need to show GUI effect window
				unless $id eq $ti{$n}->vol
					or $id eq $ti{$n}->pan;
			
			# does this do anything?
			add_effect({
						chain => $fx->{applied}->{$id}->{chain},
						type => $fx->{applied}->{$id}->{type},
						effect_id => $id,
						owns => $fx->{applied}->{$id}->{owns},
						parent_id => $fx->{applied}->{$id}->{belongs_to},
						});

		}
	} @tracks_data;


	#print "\n---\n", $main->dump;  
	#print "\n---\n", map{$_->dump} Audio::Nama::Track::all();# exit; 
	$did_apply and $ui->manifest;
	logpkg(__FILE__,__LINE__,'debug', sub{ join " ", map{ ref $_, $/ } Audio::Nama::Track::all() });


	# restore Alsa mixer settings
	if ( $config->{opts}->{a} ) {
		my $filename = $filename; 
		$filename =~ s/\.yml$//;
		print "restoring ALSA settings\n";
		print qx(alsactl -f $filename.alsa restore);
	}

	# text mode marks 

 	map
    {
		my %h = %$_;
		my $mark = Audio::Nama::Mark->new( %h ) ;
    } 
    grep { (ref $_) =~ /HASH/ } @marks_data;

	$ui->restore_time_marks();
	$ui->paint_mute_buttons;

	# track fades
	
	map{ 
		my %h = %$_; 
		my $fade = Audio::Nama::Fade->new( %h ) ;
	} @fade_data;

	# edits 
	
	map{ 
		my %h = %$_; 
		my $edit = Audio::Nama::Edit->new( %h ) ;
	} @edit_data;

	# restore command history
	
	$text->{term}->SetHistory(@{$text->{command_history}})
		if (ref $text->{command_history}) =~ /ARRAY/;

;
	# restore effect chains and profiles
	
	#say "Project Effect Chain Data\n", json_out( \@project_effect_chain_data);
 	map { my $fx_chain = Audio::Nama::EffectChain->new(%$_) } 
		(@project_effect_chain_data, @global_effect_chain_data)
} 
sub is_nonempty_hash {
	my $ref = shift;
	return if (ref $ref) !~ /HASH/;
	return (keys %$ref);
}
	 

sub save_global_effect_chains {

	@global_effect_chain_data  = map{ $_->as_hash } Audio::Nama::EffectChain::find(global => 1);

	# always save global effect chain data because it contains
	# incrementing counter

	map{ 	my $format = $_ ;
			serialize(
				file => $file->global_effect_chains,
				format => $format,
				vars => \@global_effect_chain_vars, 
				class => 'Audio::Nama',
			);
	} $config->serialize_formats;

}

# unneeded after conversion - DEPRECATED
sub save_project_effect_chains {
	my $project = shift; # allow to cross multiple projects
	@project_effect_chain_data = map{ $_->as_hash } Audio::Nama::EffectChain::find(project => $project);
}
sub restore_global_effect_chains {

	logsub("&restore_global_effect_chains");
		my $path =  $file->global_effect_chains;
		my ($resolved, $format) = get_newest($path);  
		throw("$resolved: file not found"), return unless $resolved;
		my $source = read_file($resolved);
		throw("$resolved: empty file"), return unless $source;
		logpkg(__FILE__,__LINE__,'debug', "format: $format, source: \n",$source);
		my $ref = decode($source, $format);
		logpkg(__FILE__,__LINE__,'debug', sub{Dumper $ref});
		assign(
				data => $ref,
				vars   => \@global_effect_chain_vars, 
				class => 'Audio::Nama');
}
sub git_snapshot {
	logsub("&git_snapshot");
	return unless $config->{use_git};
	return unless state_changed();
	my $commit_message = shift() || "no comment";
	git_commit($commit_message);
}
	
sub git_commit {
	logsub("&git_commit");
	my $commit_message = shift;
	$commit_message = join "\n", 
		$commit_message,
		# context for first command
		"Context:",
		" + track: $project->{undo_buffer}->[0]->{context}->{track}",
		" + bus:   $project->{undo_buffer}->[0]->{context}->{bus}",
		" + op:    $project->{undo_buffer}->[0]->{context}->{op}",
		# all commands since last commit
		map{ $_->{command} } @{$project->{undo_buffer}};
		
	git( add => $file->git_state_store );
	git( commit => '--quiet', '--message', $commit_message);
	$project->{undo_buffer} = [];
}
	

sub git_tag { 
	logsub("&git_tag");
	return unless $config->{use_git};
	my ($tag_name,$msg) = @_;
	my @args = ($tag_name);
	push(@args, '-m',$msg) if $msg;
	git( tag => @args);
}
sub git_checkout {
	logsub("&git_checkout");
	my ($branchname, @args) = @_;
	return unless $config->{use_git};

	my $exist_message = git_branch_exists($branchname)
				?  undef
				: "$branchname: branch does not exist.";
	my $dirty_tree_msg  = !! state_changed() 
		?  "You have changes to working files.
You cannot switch branches until you commit
these changes, or throw them away."
		: undef;
		
	my $conjunction = ($dirty_tree_msg and $exist_message) 
			? "And by the way, "
			: undef;

	throw( $dirty_tree_msg, 
			$conjunction, 
			$exist_message, 
			"No action taken."), return
		if $dirty_tree_msg or $exist_message;

	git(checkout => $branchname, @args);

}
sub git_create_branch {
	logsub("&git_create_branch");
	my ($branchname, $branchfrom) = @_;
	return unless $config->{use_git};
	# create new branch
	my @args;
	my $from_target;
	$from_target = "from $branchfrom" if $branchfrom;
	push @args, $branchname;
	push(@args, $branchfrom) if $branchfrom;
	pager("Creating branch $branchname $from_target");
	git(checkout => '-b', @args)
}

sub state_changed {  
	logsub("&state_changed");
	return unless $config->{use_git};
	git("diff");
}

sub git_branch_exists { 
	logsub("&git_branch_exists");
	return unless $config->{use_git};
	my $branchname = shift;
	grep{ $_ eq $branchname } 
		map{ s/^\s+//; s/^\* //; $_}
		git("branch");
}

sub current_branch {
	logsub("&current_branch");
	return unless $project->{repo};
	my ($b) = map{ /\* (\S+)/ } grep{ /\*/ } split "\n", git('branch');
	$b
}

sub git_sha {
	my $commit = shift || 'HEAD';
		my ($sha) = git(show => $commit) =~ /commit ([0-9a-f]{10})/;
		$sha
}
sub git_branch_display {
	logsub("&git_branch_display");
	return unless $config->{use_git};
	return unless current_branch();
	"( ".current_branch()." ) "
}
sub list_branches {
	pager3(
		"---Branches--- (asterisk marks current branch)",
		$project->{repo}->run('branch'),
		"",
		"-----Tags-----",
		$project->{repo}->run('tag','--list')	
	);
}

sub autosave {
	logsub("&autosave");
	my ($original_branch) = current_branch();
	my @args = qw(undo --quiet);
	unshift @args, '-b' if ! git_branch_exists('undo');
	git(checkout => @args);
	save_state();
	git_snapshot();
	git_checkout($original_branch, '--quiet');

}

sub merge_undo_branch {
	logsub("&merge_undo_branch");
	my $this_branch = current_branch();
	autosave();
	return unless my $diff = git(diff => $this_branch, 'undo');
	git( qw{ merge --no-ff undo -m}, q{merge autosave commits} );
	git( qw{ branch -d undo } );
}

1;
=comment

VI-like user reponsibility for save

save # serialize commit if autosave

merge undo branch if autosave

save foo: # serialize tag-foo foo.json


save foo: tag-foo.1 foo.json

load foo, prefer highest foo,
but if foo.json is newer, take
that. 

load foo      # find
load foo.json # load the file
load tag foo  # load the tag







__END__