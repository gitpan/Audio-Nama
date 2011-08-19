# --------- Project related subroutines ---------

package Audio::Nama;
use Modern::Perl;
use Carp;
use File::Slurp;

our (
	$debug,
	$debug2,
	$ui,
	$cop_id,
	%cops,
	%copp,
	@input_chains,
	@output_chains,
	$preview,
	$mastering_mode,
	$saved_version,
	%bunch,
	$this_bus,
	%inputs,
	%outputs,
	%wav_info,
	$offset_run_flag,
	$this_edit,
	$project_name,
	$state_store_file,
	%opts,
	%tn,
	%track_widget,
	%effects_widget,
	$markers_armed,
	@already_muted,
	$old_snapshot,
	$initial_user_mode,
	$project,	
	$project_root,
);
our ( 					# for create_system_buses
	%is_system_bus,
	@system_buses,
	$main,
	$null,
);

our ($term, %bn); 		# for project templates

{ # OPTIMIZATION

  # we allow for the (admitted rare) possibility that
  # $project_root may change

my %proot;
sub project_root { 
	$proot{$project_root} ||= resolve_path($project_root)
}
}

sub config_file { $opts{f} ? $opts{f} : ".namarc" }

{ # OPTIMIZATION
my %wdir; 
sub this_wav_dir {
	$opts{p} and return $project_root; # cwd
	$project_name and
	$wdir{$project_name} ||= resolve_path(
		join_path( project_root(), $project_name, q(.wav) )  
	);
}
}

sub project_dir {
	$opts{p} and return $project_root; # cwd
	$project_name and join_path( project_root(), $project_name) 
}

sub list_projects {
	my $projects = join "\n", sort map{
			my ($vol, $dir, $lastdir) = File::Spec->splitpath($_); $lastdir
		} File::Find::Rule  ->directory()
							->maxdepth(1)
							->extras( { follow => 1} )
						 	->in( project_root());
	pager($projects);
}

sub initialize_project_data {
	$debug2 and print "&initialize_project_data\n";

	return if transport_running();
	$ui->destroy_widgets();
	$ui->project_label_configure(
		-text => uc $project_name, 
		-background => 'lightyellow',
		); 

	# effect variables - no object code (yet)
	
	$cop_id = "A"; # autoincrement counter
	%cops	= ();  # effect and controller objects (hashes)
	%copp   = ();  # chain operator parameters
	               # indexed by {$id}->[$param_no]
	               # zero-based {AB}->[0] (parameter 1)

	@input_chains = ();
	@output_chains = ();

	%track_widget = ();
	%effects_widget = ();

	$markers_armed = 0;

	map{ $_->initialize() } qw(
							Audio::Nama::Mark
							Audio::Nama::Fade
							Audio::Nama::Edit
							Audio::Nama::Bus
							Audio::Nama::Track
							Audio::Nama::Insert
							);
	
	# volume settings
	
	@already_muted = ();

	# $is_armed = 0;
	
	$old_snapshot = {};
	$preview = $initial_user_mode;
	$mastering_mode = 0;
	$saved_version = 0; 
	
	%bunch = ();	
	
	create_system_buses();
	$this_bus = 'Main';

	%inputs = %outputs = ();
	
	%wav_info = ();
	
	clear_offset_run_vars();
	$offset_run_flag = 0;
	$this_edit = undef;

}
sub load_project {
	$debug2 and print "&load_project\n";
	my %h = @_;
	$debug and print yaml_out \%h;
	print("no project name.. doing nothing.\n"),return 
		unless $h{name} or $project;
	$project_name = $h{name} if $h{name};

	if ( ! -d join_path( project_root(), $project_name) ){
		if ( $h{create} ){
			map{create_dir($_)} &project_dir, &this_wav_dir ;
		} else { 
			print qq(
Project "$project_name" does not exist. 
Loading project "untitled".
);
			load_project( qw{name untitled create 1} );
			return;
		}
	} 
	# we used to check each project dir for customized .namarc
	# read_config( global_config() ); 
	
	teardown_engine(); # initialize_ecasound_engine; 
	initialize_project_data();
	remove_riff_header_stubs(); 
	cache_wav_info();
	rememoize();

	restore_state( $h{settings} ? $h{settings} : $state_store_file) unless $opts{M} ;
	if (! $tn{Master}){

		Audio::Nama::SimpleTrack->new( 
			group => 'Master', 
			name => 'Master',
			send_type => 'soundcard',
			send_id => 1,
			width => 2,
			rw => 'MON',
			source_type => undef,
			source_id => undef); 

		my $mixdown = Audio::Nama::MixDownTrack->new( 
			group => 'Mixdown', 
			name => 'Mixdown', 
			width => 2,
			rw => 'OFF',
			source_type => undef,
			source_id => undef); 

		#remove_effect($mixdown->vol);
		#remove_effect($mixdown->pan);
	}


	$opts{M} = 0; # enable 
	
	dig_ruins() unless scalar @Audio::Nama::Track::all > 2;

	# possible null if Text mode
	
	$ui->global_version_buttons(); 
	$ui->refresh_group;

	$debug and print "project_root: ", project_root(), $/;
	$debug and print "this_wav_dir: ", this_wav_dir(), $/;
	$debug and print "project_dir: ", project_dir() , $/;

 1;
}	

sub dig_ruins { # only if there are no tracks 
	
	$debug2 and print "&dig_ruins";
	return if Audio::Nama::Track::user();
	$debug and print "looking for WAV files\n";

	# look for wave files
		
	my $d = this_wav_dir();
	opendir my $wav, $d or carp "couldn't open $d: $!";

	# remove version numbers
	
	my @wavs = grep{s/(_\d+)?\.wav//i} readdir $wav;

	closedir $wav;

	my %wavs;
	
	map{ $wavs{$_}++ } @wavs;
	@wavs = keys %wavs;

	$debug and print "tracks found: @wavs\n";
 
	$ui->create_master_and_mix_tracks();

	map{add_track($_)}@wavs;

}

sub remove_riff_header_stubs {

	# 44 byte stubs left by a recording chainsetup that is 
	# connected by not started
	
	$debug2 and print "&remove_riff_header_stubs\n";
	

	$debug and print "this wav dir: ", this_wav_dir(), $/;
	return unless this_wav_dir();
         my @wavs = File::Find::Rule ->name( qr/\.wav$/i )
                                        ->file()
                                        ->size(44)
                                        ->extras( { follow => 1} )
                                     ->in( this_wav_dir() );
    $debug and print join $/, @wavs;

	map { unlink $_ } @wavs; 
}

sub create_system_buses {
	$debug2 and say "&create_system_buses";

	my $buses = q(
			Master		# master fader track
			Mixdown		# mixdown track
			Mastering	# mastering network
			Insert		# auxiliary tracks for inserts
			Cooked		# for track caching
			Temp		# temp tracks while generating setup
			Main		# default mixer bus, new tracks assigned to Main
	);
	($buses) = strip_comments($buses); # need initial parentheses
	@system_buses = split " ", $buses;
	map{ $is_system_bus{$_}++ } @system_buses;
	delete $is_system_bus{Main}; # because we want to display it
	map{ Audio::Nama::Bus->new(name => $_ ) } @system_buses;
	
	# a bus should identify it's mix track
	$bn{Main}->set( send_type => 'track', send_id => 'Master');

	$main = $bn{Main};
	$null = $bn{null};
}


## project templates

sub new_project_template {
	my ($template_name, $template_description) = @_;

	my @tracks = Audio::Nama::Track::all();

	# skip if project is empty

	say("No user tracks found, aborting.\n",
		"Cannot create template from an empty project."), 
		return if scalar @tracks < 3;

	# save current project status to temp state file 
	
	my $previous_state = '_previous_state.yml';
	save_state($previous_state);

	# edit current project into a template
	
	# No tracks are recorded, so we'll remove 
	#	- version (still called 'active')
	# 	- track caching
	# 	- region start/end points
	# 	- effect_chain_stack
	# Also
	# 	- unmute all tracks
	# 	- throw away any pan caching

	map{ my $track = $_;
		 $track->unmute;
		 map{ $track->set($_ => undef)  } 
			qw( version	
				old_pan_level
				region_start
				region_end
			);
		 map{ $track->set($_ => [])  } 
			qw(	effect_chain_stack      
			);
		 map{ $track->set($_ => {})  } 
			qw( cache_map 
			);
		
	} @tracks;

	# Throw away command history
	
	$term->SetHistory();
	
	# Buses needn't set version info either
	
	map{$_->set(version => undef)} values %bn;
	
	# create template directory if necessary
	
	mkdir join_path(project_root(), "templates");

	# save to template name
	
	save_state( join_path(project_root(), "templates", "$template_name.yml"));

	# add description, but where?
	
	# recall temp name
	
 	load_project(  # restore_state() doesn't do the whole job
 		name     => $project_name,
 		settings => $previous_state,
	);

	# remove temp state file
	
	unlink join_path( project_dir(), "$previous_state.yml") ;
	
}
sub use_project_template {
	my $name = shift;
	my @tracks = Audio::Nama::Track::all();

	# skip if project isn't empty

	say("User tracks found, aborting. Use templates in an empty project."), 
		return if scalar @tracks > 2;

	# load template
	
 	load_project(
 		name     => $project_name,
 		settings => join_path(project_root(),"templates",$name),
	);
	save_state();
}
sub list_project_templates {
	my $read = read_file(join_path(project_root(), "templates"));
	push my @templates, "\nTemplates:\n", map{ m|([^/]+).yml$|; $1, "\n"} $read;        
	pager(@templates);
}
sub remove_project_template {
	map{my $name = $_; 
		say "$name: removing template";
		$name .= ".yml" unless $name =~ /\.yml$/;
		unlink join_path( project_root(), "templates", $name);
	} @_;
	
}
1;
__END__