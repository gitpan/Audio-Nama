# ----------- Initialize --------
#
#
#  These routines are executed once on program startup
#
#

package Audio::Nama;
use Modern::Perl; use Carp;
use Socket qw(getnameinfo NI_NUMERICHOST) ;

sub apply_test_harness {

	push @ARGV, qw(-f /dev/null), # force to use internal namarc

				qw(-t), # set text mode 

				qw(-d), $Audio::Nama::test_dir,
				
				q(-E), # suppress loading Ecasound

				q(-J), # fake jack client data

				q(-T), # don't initialize terminal
                       # load fake effects cache

				q(-S), # don't load static effects data

				#qw(-L SUB), # logging

	$jack->{periodsize} = 1024;
}
sub apply_ecasound_test_harness {
	apply_test_harness();
	@ARGV = grep { $_ ne q(-E) } @ARGV
}

sub definitions {

	$| = 1;     # flush STDOUT buffer on every write

	$ui eq 'bullwinkle' or die "no \$ui, bullwinkle";

	@global_effect_chain_vars  = qw(

	@global_effect_chain_data 
	$Audio::Nama::EffectChain::n 
	$fx->{alias}
);
@tracked_vars = qw(

	@tracks_data
	@bus_data
	@groups_data
	@marks_data
	@fade_data
	@edit_data
	@inserts_data

	$project->{save_file_version_number}
	
	$fx->{applied}
	$fx->{params}
	$fx->{params_log}

);
@persistent_vars = qw(

	$project->{save_file_version_number}
	$project->{timebase}
	$project->{command_buffer}
	$project->{track_version_comments}
	$project->{track_comments}
	$project->{bunch}
	$project->{current_op}
	$project->{current_param}
	$project->{current_stepsize}
	$project->{playback_position}
	@project_effect_chain_data
	$fx->{id_counter}
	$setup->{loop_endpoints}
	$mode->{loop_enable}
	$mode->{mastering}
	$mode->{preview}
	$mode->{midish_terminal}
	$mode->{midish_transport_sync}
	$gui->{_seek_unit}
	$text->{command_history}
	$this_track_name
	$this_op
);



	$text->{wrap} = new Text::Format {
		columns 		=> 75,
		firstIndent 	=> 0,
		bodyIndent		=> 0,
		tabstop			=> 4,
	};

	####### Initialize singletons #######

	# Some of these "singletons" (imported by 'use Globals')
	# are just hashes, some have object behavior as
	# the sole instance of their class.
	
	$project = bless {}, 'Audio::Nama::Project';
	$mode = bless {}, 'Audio::Nama::Mode';
	{ package Audio::Nama::Mode; 
		sub mastering 	{ $Audio::Nama::tn{Eq} and ! $Audio::Nama::tn{Eq}->{hide} } 
		no warnings 'uninitialized';
		sub eager 		{ $Audio::Nama::mode->{eager} 					}
		sub doodle 		{ 
			#my $set = shift;
			#if (defined $set){ $Audio::Nama::mode->{preview} = $set ? 'doodle' : 0 }
			$Audio::Nama::mode->{preview} eq 'doodle' 	}
		sub preview 	{ $Audio::Nama::mode->{preview} eq 'preview' 	}
		sub song 		{ $Audio::Nama::mode->eager and $Audio::Nama::mode->preview }
		sub live		{ $Audio::Nama::mode->eager and $Audio::Nama::mode->doodle  }
	}
	# for example, $file belongs to class Audio::Nama::File, and uses
	# AUTOLOAD to generate methods to provide full path
	# to various system files, such as $file->state_store
	{
	package Audio::Nama::File;
		use Carp;
		sub logfile {
			my $self = shift;
			$ENV{NAMA_LOGFILE} || $self->_logfile
		}
		sub AUTOLOAD {
			my ($self, $filename) = @_;
			# get tail of method call
			my ($method) = $Audio::Nama::File::AUTOLOAD =~ /([^:]+)$/;
			croak "$method: illegal method call" unless $self->{$method};
			my $dir_sub = $self->{$method}->[1];
			$filename ||= $self->{$method}->[0];
			my $path = Audio::Nama::join_path($dir_sub->(), $filename);
			$path;
		}
		sub DESTROY {}
		1;
	}
	$file = bless 
	{
		effects_cache 			=> ['.effects_cache', 		\&project_root],
		gui_palette 			=> ['palette',        		\&project_root],
		state_store 			=> ['State',      			\&project_dir ],
		git_state_store 		=> ['State.json',      		\&project_dir ],
		untracked_state_store => ['Aux',					\&project_dir ],
		effect_profile 			=> ['effect_profiles',		\&project_root],
		chain_setup 			=> ['Setup.ecs',      		\&project_dir ],
		user_customization 		=> ['customize.pl',    		\&project_root],
		project_effect_chains 	=> ['project_effect_chains',\&project_dir ],
		global_effect_chains  	=> ['global_effect_chains', \&project_root],
		old_effect_chains  		=> ['effect_chains', 		\&project_root],
		_logfile				=> ['nama.log',				\&project_root],


	}, 'Audio::Nama::File';

	$gui->{_save_id} = "State";
	$gui->{_seek_unit} = 1;
	$gui->{marks} = {};


# 
# use this section to specify 
# defaults for config variables 
#
# These are initial, lowest priority defaults
# defaults for Nama config. Some variables
# may be overwritten during subsequent read_config's
#
# config variable sources are prioritized as follows

	#
	#		+   command line argument -f /path/to/namarc 
	#		+   project specific namarc  # currently disabled
	#		+	user namarc (usually ~/.namarc)
	#		+	internal namarc
	#		+	internal initialization


	$config = bless {
		root_dir 						=> join_path( $ENV{HOME}, "nama"),
		soundcard_channels 				=> 10,
		memoize 						=> 1,
		use_pager 						=> 1,
		use_placeholders 				=> 1,
		use_git							=> 1,
		autosave						=> 'undo',
		volume_control_operator 		=> 'ea', # default to linear scale
		sync_mixdown_and_monitor_version_numbers => 1, # not implemented yet
		engine_tcp_port					=> 2868, # 'default' engine
		engine_fade_length_on_start_stop => 0.18,# when starting/stopping transport
		engine_fade_default_length 		=> 0.5, # for fade-in, fade-out
		engine_base_jack_seek_delay 	=> 0.1, # seconds
		edit_playback_end_margin 		=> 3,
		edit_crossfade_time 			=> 0.03,
		fade_down_fraction 				=> 0.75,
		fade_time1_fraction 			=> 0.9,
		fade_time2_fraction 			=> 0.1,
		fader_op 						=> 'ea',
		mute_level 						=> {ea => 0, 	eadb => -96}, 
		fade_out_level 					=> {ea => 0, 	eadb => -40},
		unity_level 					=> {ea => 100, 	eadb => 0}, 
		fade_resolution 				=> 100, # steps per second
		engine_muting_time				=> 0.03,
		enforce_channel_bounds			=> 1,

		serialize_formats               => 'json',		# for save_system_state()

		latency_op						=> 'el:delay_n',
		latency_op_init					=> [0,0],
		latency_op_set					=> sub
			{
				my $id = shift;
				my $delay = shift();
				modify_effect($id,2,undef,$delay)
			},
		hotkey_beep					=> 'beep -f 250 -l 200',
	#	this causes beeping during make test
	#	beep_command					=> 'beep -f 350 -l 700',

	}, 'Audio::Nama::Config';

	{ package Audio::Nama::Config;
	use Carp;
	use Audio::Nama::Globals qw(:singletons);
	use Modern::Perl;
	our @ISA = 'Audio::Nama::Object'; #  for ->dump and ->as_hash methods

	sub serialize_formats { split " ", $_[0]->{serialize_formats} }

	sub hardware_latency {
		no warnings 'uninitialized';
		$config->{devices}->{$config->{alsa_capture_device}}{hardware_latency} || 0
	}
 	sub buffersize {
		package Audio::Nama;
 		Audio::Nama::ChainSetup::setup_requires_realtime()
 			? ($config->{engine_buffersize}->{realtime}->{jack_period_multiple}
				&& $jack->{jackd_running}
				&& $config->{engine_buffersize}->{realtime}->{jack_period_multiple}
					* $jack->{periodsize}
				|| $config->{engine_buffersize}->{realtime}->{default}
 			)
 			: (	$config->{engine_buffersize}->{nonrealtime}->{jack_period_multiple}
				&& $jack->{jackd_running}
				&&  $config->{engine_buffersize}->{nonrealtime}->{jack_period_multiple}
					* $jack->{periodsize}
				|| $config->{engine_buffersize}->{nonrealtime}->{default}
 			)
 	}
	sub globals_realtime {
		Audio::Nama::ChainSetup::setup_requires_realtime()
			? $config->{engine_globals}->{realtime}
			: $config->{engine_globals}->{nonrealtime}
	}
	} # end Audio::Nama::Config package

	$prompt = "nama ('h' for help)> ";

	$this_bus = 'Main';
	
	$setup->{_old_snapshot} = {};
	$setup->{_last_rec_tracks} = [];

	$mastering->{track_names} = [ qw(Eq Low Mid High Boost) ];

	init_wav_memoize() if $config->{memoize};

}

sub initialize_interfaces {
	
	logsub("&intialize_interfaces");

	if ( ! $config->{opts}->{t} and Audio::Nama::Graphical::initialize_tk() ){ 
		$ui = Audio::Nama::Graphical->new();
	} else {
		pager_newline( "Unable to load perl Tk module. Starting in console mode.") if $config->{opts}->{g};
		$ui = Audio::Nama::Text->new();
		can_load( modules =>{ Event => undef})
			or die "Perl Module 'Event' not found. Please install it and try again. Stopping.";
;
		import Event qw(loop unloop unloop_all);
	}
	
	can_load( modules => {AnyEvent => undef})
			or die "Perl Module 'AnyEvent' not found. Please install it and try again. Stopping.";
	use AnyEvent::TermKey qw( FORMAT_VIM KEYMOD_CTRL ); 
	can_load( modules => {jacks => undef})
		and $jack->{use_jacks}++;
	choose_sleep_routine();
	$config->{want_logging} = initialize_logger($config->{opts}->{L});

	$project->{name} = shift @ARGV;
	{no warnings 'uninitialized';
	logpkg(__FILE__,__LINE__,'debug',"project name: $project->{name}");
	}

	logpkg(__FILE__,__LINE__,'debug', sub{"Command line options\n".  json_out($config->{opts})});

	read_config(global_config());  # from .namarc if we have one

	# overwrite default hotkey bindings by those in .namarc 
	$config->{hotkeys} = {
		%{json_in(get_data_section 'hotkey_bindings') },
		%{$config->{hotkeys} } 
	};
	
	logpkg(__FILE__,__LINE__,'debug',sub{"Config data\n".Dumper $config});
	
	select_ecasound_interface();
		
	start_osc_listener($config->{osc_listener_port}) 
		if $config->{osc_listener_port} 
		and can_load(modules => {'Protocol::OSC' => undef});
	start_remote_listener($config->{remote_control_port}) if $config->{remote_control_port};
	logpkg(__FILE__,__LINE__,'debug',"reading config file");
	if ($config->{opts}->{d}){
		pager("project_root $config->{opts}->{d} specified on command line\n");
		$config->{root_dir} = $config->{opts}->{d};
	}
	if ($config->{opts}->{p}){
		$config->{root_dir} = getcwd();
		pager("placing all files in current working directory ($config->{root_dir})\n");
	}

	# skip initializations if user (test) supplies project
	# directory
	
	first_run() unless $config->{opts}->{d}; 

	#my $fx_cache_json;
	#$fx_cache_json = get_data_section("fx_cache") if $config->{opts}->{T};
	prepare_static_effects_data() unless $config->{opts}->{S};
	setup_user_customization();	# depends on effect_index() in above

	get_ecasound_iam_keywords();
	load_keywords(); # for autocompletion

	chdir $config->{root_dir} # for filename autocompletion
		or warn "$config->{root_dir}: chdir failed: $!\n";

	$ui->init_gui;
	$ui->transport_gui;
	$ui->time_gui;

	
	# fake JACK for testing environment

	if( $config->{opts}->{J}){
		parse_ports_list(get_data_section("fake_jack_lsp"));
		parse_port_latency(get_data_section("fake_jack_latency"));
		$jack->{jackd_running} = 1;
	}

	# periodically check if JACK is running, and get client/port/latency list

	poll_jack() unless $config->{opts}->{J} or $config->{opts}->{A};

	sleeper(0.2); # allow time for first polling

	# we will start jack.plumbing only when we need it
	
	if(		$config->{use_jack_plumbing} 
	and $jack->{jackd_running} 
	and process_is_running('jack.plumbing')
	){

		pager_newline(<<PLUMB);
Jack.plumbing daemon detected!

Attempting to stop it...  

(This may break other software that depends in jack.plumbing.)

Nama will restart it as needed for Nama's use only.
PLUMB

		kill_jack_plumbing();
		sleeper(0.2);
		if( process_is_running('jack.plumbing') )
		{
		throw(q(Unable to stop jack.plumbing daemon.

Please do one of the following, then restart Nama:

 - kill the jack.plumbing daemon ("killall jack.plumbing")
 - set "use_jack_plumbing: 0" in .namarc

....Exiting.) );
exit;
		}
		else { pager_newline("Stopped.") }
	}
		
	start_midish() if $config->{use_midish};

	initialize_terminal() unless $config->{opts}->{T};

	# set default project to "untitled"
	
	#convert_project_format(); # mark with .conversion_completed file in ~/nama
	
	if (! $project->{name} ){
		$project->{name} = "untitled";
		$config->{opts}->{c}++; 
	}
	pager("\nproject_name: $project->{name}\n");
	
	load_project( name => $project->{name}, create => $config->{opts}->{c}) ;
	1;	
}
{ my $is_connected_remote;
sub start_remote_listener {
    my $port = shift;
    pager_newline("Starting remote control listener on port $port");
    $project->{remote_control_socket} = IO::Socket::INET->new( 
        LocalAddr   => 'localhost',
        LocalPort   => $port, 
        Proto       => 'tcp',
        Type        => SOCK_STREAM,
        Listen      => 1,
        Reuse       => 1) || die $!;
    start_remote_watcher();
}
sub start_remote_watcher {
    $project->{events}->{remote_control} = AE::io(
        $project->{remote_control_socket}, 0, \&process_remote_command )
}
sub remove_remote_watcher {
    undef $project->{events}->{remote_control};
}
sub process_remote_command {
    if ( ! $is_connected_remote++ ){
        pager_newline("making connection");
        $project->{remote_control_socket} =
            $project->{remote_control_socket}->accept();
		remove_remote_watcher();
        $project->{events}->{remote_control} = AE::io(
            $project->{remote_control_socket}, 0, \&process_remote_command );
    }
    my $input;
    eval {     
        $project->{remote_control_socket}->recv($input, $project->{remote_control_socket}->sockopt(SO_RCVBUF));
    };
    $@ and throw("caught error: $@, resetting..."), reset_remote_control_socket(), revise_prompt(), return;
    logpkg(__FILE__,__LINE__,'debug',"Got remote control socketput: $input");
	process_command($input);
	my $out;
	{ no warnings 'uninitialized';
		$out = $text->{eval_result} . "\n";
	}
    eval {
        $project->{remote_control_socket}->send($out);
    };
    $@ and throw("caught error: $@, resetting..."), reset_remote_control_socket(), revise_prompt(), return;
	revise_prompt();
}
sub reset_remote_control_socket { 
    undef $is_connected_remote;
    undef $@;
    $project->{remote_control_socket}->shutdown(2);
    undef $project->{remote_control_socket};
    remove_remote_watcher();
	start_remote_listener($config->{remote_control_port});
}
}

sub start_osc_listener {
	my $port = shift;
	say("Starting OSC listener on port $port");
	my $osc_in = $project->{osc_socket} = IO::Socket::INET->new(
		LocalAddr => 'localhost',
		LocalPort => $port,
		Proto	  => 'udp',
		Type	  =>  SOCK_DGRAM) || die $!;
	$project->{events}->{osc} = AE::io( $osc_in, 0, \&process_osc_command );
	$project->{osc} = Protocol::OSC->new;
}
sub process_osc_command {
	my $in = $project->{osc_socket};
	my $osc = $project->{osc};
	my $source_ip = $in->recv(my $packet, $in->sockopt(SO_RCVBUF));
	my($err, $hostname, $servicename) = getnameinfo($source_ip, NI_NUMERICHOST);
	my $p = $osc->parse($packet);
	my @args = @$p;
	my ($path, $template, $command, @vals) = @args;
	$path =~ s(^/)();
	$path =~ s(/$)();
	my ($trackname, $fx, $param) = split '/', $path;
	process_command($trackname);
	process_command("$command @vals") if $command;
	process_command("show_effect $fx") if $fx; # select
	process_command("show_track") if $trackname and not $fx;
	process_command("show_tracks") if ! $trackname;
	say "got OSC: ", Dumper $p;
	say "got args: @args";
 	my $osc_out = IO::Socket::INET->new(
 		PeerAddr => $hostname,
 		PeerPort => $config->{osc_reply_port},
 		Proto	  => 'udp',
 		Type	  =>  SOCK_DGRAM) || die $!;
	$osc_out->send(join "",@{$text->{output_buffer}});
	delete $text->{output_buffer};
}

sub sanitize_remote_input {
	my $input = shift;
	my $error_msg;
	do{ $input = "" ; $error_msg = "error: perl/shell code is not allowed"}
		if $input =~ /(^|;)\s*(!|eval\b)/;
	throw($error_msg) if $error_msg;
	$input
}
sub select_ecasound_interface {
	Audio::Nama::Effects::import_engine_subs();
	my %args;
	my $class;
	if ($config->{opts}->{A} or $config->{opts}->{E})
	{
		pager_newline("Starting dummy engine only"); 
		%args = (
			name => 'Nama', 
			jack_transport_mode => 'send',
		);
		$class = 'Audio::Nama::Engine';
	}
	elsif (
		$config->{opts}->{l} 
		and can_load( modules => { 'Audio::Ecasound' => undef })
		and say("loaded Audio::Ecasound")
	){  
		%args = (
			name => 'Nama', 
			jack_transport_mode => 'send',
		);
		$class = 'Audio::Nama::LibEngine';
	}
	else { 
		%args = (
			name => 'Nama', 
			port => $config->{engine_tcp_port},
			jack_transport_mode => 'send',
		);
		$class = 'Audio::Nama::NetEngine';
	}
	$class->new(%args);
}



sub choose_sleep_routine {
	if ( can_load(modules => {'Time::HiRes'=> undef} ) ) 
		 { *sleeper = *finesleep;
			$config->{hires_timer}++; }
	else { *sleeper = *select_sleep }
}
sub finesleep {
	my $sec = shift;
	Time::HiRes::usleep($sec * 1e6);
}
sub select_sleep {
   my $seconds = shift;
   select( undef, undef, undef, $seconds );
}
sub munge_category {
	
	my $cat = shift;
	
	# override undefined category by magical global setting
	# default to 'ECI_OTHER'
	
	$cat  ||= ($config->{category} || 'ECI_OTHER');

	# force all categories to 'ECI' if 'ECI' is selected for logging
	# (exception: ECI_WAVINFO, which is too noisy)
	
	no warnings 'uninitialized';
	return 'ECI' if $config->{want_logging}->{ECI} and not $cat eq 'ECI_WAVINFO';

	$cat
}

sub start_logging { 
	$config->{want_logging} = initialize_logger($config->{opts}->{L})
}
sub eval_iam { $this_engine and $this_engine->eval_iam(@_) }
1;
__END__