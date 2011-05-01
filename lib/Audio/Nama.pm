## Note on object model
# 
# All graphic method are defined in the base class Audio::Nama .
# These are overridden in the Audio::Nama::Text class with no-op stubs.

# How is $ui->init_gui interpreted? If $ui is class Audio::Nama::Text
# Nama finds a no-op init_gui stub in package Audio::Nama::Text.
#
# If $ui is class Audio::Nama::Graphical, 
# Nama looks for init_gui() in package Audio::Nama::Graphical,
# finds nothing, so goes to look in the root namespace ::
# of which Audio::Nama::Text and Audio::Nama::Graphical are both descendants.

# All the routines in Graphical_methods.pl can consider
# themselves to be in the base class, and can call base
# class subroutines without a package prefix

# Text_method.pl subroutines live in the Audio::Nama::Text class,
# and so they must use the Audio::Nama prefix when calling
# subroutines in the base class.
#
# However because both subclass packages occupy the same file as 
# the base class package, all variables (defined by 'our') can 
# be accessed without a package prefix.

package Audio::Nama;
require 5.10.0;
use vars qw($VERSION);
$VERSION = 1.074;
use Modern::Perl;
#use Carp::Always;
no warnings qw(uninitialized syntax);
use autodie qw(:default);
use Carp;
use Cwd;
use Data::Section -setup;
use File::Find::Rule;
use File::Path;
use File::Spec;
use File::Spec::Link;
use File::Temp;
use Getopt::Long;
use Graph;
use IO::Socket; 
use IO::Select;
use IPC::Open3;
use Module::Load::Conditional qw(can_load); 
use Parse::RecDescent;
use Storable; 
use Term::ReadLine;
use Text::Format;
# use File::HomeDir;# Assign.pm
# use File::Slurp;  # several
# use List::Util;   # Fade.pm
# use Time::HiRes; # automatically detected
# use Tk;           # loaded conditionally
# use Event;		# loaded conditionally
# use AnyEvent;		# loaded after Tk or Event

## Load my modules

use Audio::Nama::Assign qw(:all);
use Audio::Nama::Track;
use Audio::Nama::Group;
use Audio::Nama::Bus;    
use Audio::Nama::Mark;
use Audio::Nama::IO;
use Audio::Nama::Graph;
use Audio::Nama::Wav;
use Audio::Nama::Insert;
use Audio::Nama::Fade;
use Audio::Nama::Edit;
use Audio::Nama::Text;
use Audio::Nama::Graphical;

# the following separate out functionality
# however occupy the Audio::Nama namespace

use Audio::Nama::Persistence ();
use Audio::Nama::ChainSetup ();
use Audio::Nama::CacheTrack ();
use Audio::Nama::Edit_subs ();
use Audio::Nama::Effect_subs ();
use Audio::Nama::Util qw(
	rw_set 
	process_is_running 
	d1 d2 dn 
	colonize 
	time_tag 
	heuristic_time
	dest_type
	channels
	signal_format
	dest_type
	input_node
	output_node
);
use Audio::Nama::Initialize_subs ();
use Audio::Nama::Option_subs ();
use Audio::Nama::Config_subs ();
use Audio::Nama::Terminal_subs ();
use Audio::Nama::Wavinfo_subs ();
use Audio::Nama::Project_subs ();
use Audio::Nama::Mode_subs ();
use Audio::Nama::Engine_setup_subs ();
use Audio::Nama::Engine_cleanup_subs ();
use Audio::Nama::Realtime_subs ();
use Audio::Nama::Mute_Solo_Fade ();
use Audio::Nama::Jack_subs ();
use Audio::Nama::Bus_subs ();
use Audio::Nama::Track_subs ();
use Audio::Nama::Region_subs ();
use Audio::Nama::Effect_chain_subs ();
use Audio::Nama::Mark_and_jump_subs ();
use Audio::Nama::Midi_subs ();
use Audio::Nama::Memoize_subs ();

## Definitions ##

$| = 1;     # flush STDOUT buffer on every write

# 'our' declaration: code in all packages in Nama.pm can address
# the following variables without package name prefix

our (
# category: fixed

	$banner,
	$debug,				# debug level flags for diagnostics
	$debug2,			# for subroutine names as execute
	$debug3,			# deprecated

# category: help

	$help_screen, 		 
	@help_topic,    # array of help categories
	%help_topic,    # help text indexed by topic

# category: text UI

	$use_pager,     # display lengthy output data using pager
	$use_placeholders,  # use placeholders in show_track output

	$grammar, 		# filled by Grammar.pm
	$parser,		# for the objected created by Parse::RecDescent
	$text_wrap,		# Text::Format object
	@format_fields, # data for replies to text commands
	
	$commands_yml,	# commands.yml as string
	%commands,		# created from commands.yml
	%iam_cmd,		# dictionary of Ecasound IAM commands
	@nama_commands,
	%nama_commands,	# as hash

	$term, 			# Term::ReadLine object
	$previous_text_command, # to check for repetition
	@keywords,      # for autocompletion
    $prompt,
	$attribs,       # Term::Readline::Gnu object
	$format_top,    # show_tracks listing
	$format_divider,

	$custom_pl,    # default customization file
	%user_command,
	%user_alias,

# category: UI

	$ui, # object providing class behavior for graphic/text functions

# category: serialization

	@persistent_vars, # a set of variables we save
	@effects_static_vars,# the list of which variables to store and retrieve
	@config_vars,    # contained in config file

# category: config
	
	%opts,          # command line options
	$default,		# the internal default configuration file, as string

# category: routing

	$preview,       # for preview and doodle modes
	
# category: engine, realtime operation

	$ecasound, 		# the name to invoke when we want to kill ecasound
	@ecasound_pids,	# processes started by Nama
	$e,				# the name of the variable holding
					# the Ecasound engine object.
	$run_time,		# engine processing time limit (none if undef)
	$seek_delay,    # delay to allow engine to seek 
					# under JACK before restart
	$fade_time, 	# duration for fadein(), fadeout()

# category: MIDI
					
	%midish_command,	# keywords listing
	$midi_input_dev,
	$midi_output_dev, 
	$controller_ports,	# where we listen for MIDI messages
    $midi_inputs,		# on/off/capture

# category: filenames

	$effects_cache_file, # where we keep info on Ecasound
					# and LADSPA effects, presets, etc.
	$state_store_file,	# filename for storing @persistent_vars
	$effect_chain_file, # for storing effect chains
	$effect_profile_file, # for storing effect templates
	$chain_setup_file, 	# Ecasound uses this 
	$user_customization_file, 


# category: pronouns

	$this_track,	# the currently active track -- 
					# used by Text UI only at present
	$this_mark,    	# current mark  # for future
	$this_bus, 		# current bus
	$this_edit,		# current edit

# category: project

	$project_name,	# current project name

	# buses
	
	$main_bus, 
	$main, # main group
	$null_bus,
    $null, # null group
	@system_buses, 
	%is_system_bus, 

	# aliases
	
	%ti, # track by index (alias to %Audio::Nama::Track::by_index)
	%tn, # track by name  (alias to %Audio::Nama::Track::by_name)
	%bn, # bus   by name  (alias to %Audio::Nama::Bus::by_name)

# category: effects

	$magical_cop_id, # cut through five levels of subroutines
	$cop_hints_yml,  # ecasound effects hints

	%offset,        # index by chain, offset for user-visible effects 
					# pertains to engine

	@mastering_effect_ids,        # effect ids for mastering mode
	$tkeca_effects_data,	# original tcl code, actually
	%L,
	%M,

	@already_muted, # for soloing, a list of Track objects that are 
					# muted before we begin
    $soloing,       # one user track is on, all others are muted

	%effect_chain, # named effect sequences
	%effect_profile, # effect chains for multiple tracks

	%mute_level,	# 0 for ea as vol control, -127 for eadb
	%fade_out_level, # 0 for ea, -40 for eadb
	$fade_resolution, # steps per second
	%unity_level,	# 100 for ea, 0 for eadb
	
	$default_fade_length, 

# category: external resources (ALSA, JACK, etc.)

 	$jack_system,   # jack soundcard device
	$jack_running,  # jackd server status 
	$jack_plumbing, # jack.plumbing daemon status
	$jack_lsp,      # jack_lsp -Ap
	$fake_jack_lsp, # for testing
	%jack,			# jack clients data from jack_lsp
	$sampling_frequency, # of souncard

# category: events

	%event_id,    # events will store themselves with a key

	%duplicate_inputs, # named tracks will be OFF in doodle mode
	%already_used,  #  source => used_by

	$memoize,       # do I cache this_wav_dir?
	$hires,        # do I have Timer::HiRes?

	$old_snapshot,  # previous status_snapshot() output
					# to check if I need to reconfigure engine
	%old_rw,       # previous track rw settings (indexed by track name)
	
	@mastering_track_names, # reserved for mastering mode

	$disable_auto_reconfigure, # for debugging

	%cooked_record_pending, # an intermediate mixdown for tracks
	$sock, 			# socket for Net-ECI mode
	%versions,		# store active versions for use after engine run
	$track_snapshots, # to save recalculating for each IO object
	$regenerate_setup, # force us to generate new chain setup
	
	%wav_info,			# caches path/length/format/modify-time
	
# category: edits

	$offset_run_flag, # indicates edit or offset_run mode
	$offset_run_start_time,
	$offset_run_end_time,
	$offset_mark,

	@edit_points, 
	$edit_playback_end_margin, # play a little more after edit recording finishes
	$edit_crossfade_time,
	$last_edit_name,	# for save/restore

# category: Graphical UI, GUI

	$tk_input_channels,# for menubutton
	
	# variables for GUI text input widgets

	$project,		
	$track_name,
	$ch_r,			# recording channel assignment
	$ch_m,			# monitoring channel assignment
	$save_id,		# name for save file

	$default_palette_yml, # default GUI colors

	# Widgets
	
	$mw, 			# main window
	$ew, 			# effects window
	$canvas, 		# to lay out the effects window

	# each part of the main window gets its own frame
	# to control the layout better

	$load_frame,
	$add_frame,
	$group_frame,
	$time_frame,
	$clock_frame,
	$oid_frame,
	$track_frame,
	$effect_frame,
	$iam_frame,
	$perl_eval_frame,
	$transport_frame,
	$mark_frame,
	$fast_frame, # forward, rewind, etc.

	## collected widgets (i may need to destroy them)

	%parent, # ->{mw} = $mw; # main window
			 # ->{ew} = $ew; # effects window
			 # eventually will contain all major frames
	$group_label, 
	$group_rw, # 
	$group_version, # 
	%track_widget, # for chains (tracks)
	%track_widget_remove, # what to destroy by remove_track
	%effects_widget, # for effects
	@widget_o, # for templates (oids) 
	%widget_o, # 
	%mark_widget, # marks

	@global_version_buttons, # to set the same version for
						  	#	all tracks
	$markers_armed, # set true to enable removing a mark
	$mark_remove,   # a button that sets $markers_armed
	$time_step,     # widget shows jump multiplier unit (seconds or minutes)
	$clock, 		# displays clock
	$setup_length,  # displays setup running time

	$project_label,	# project name

	$sn_label,		# project load/save/quit	
	$sn_text,
	$sn_load,
	$sn_new,
	$sn_quit,
	$sn_palette, # configure default master window colors
	$sn_namapalette, # configure nama-specific master-window colors
	$sn_effects_palette, # configure effects window colors
	@palettefields, # set by setPalette method
	@namafields,    # field names for color palette used by nama
	%namapalette,     # nama's indicator colors
	%palette,  # overall color scheme
	$rec,      # background color
	$mon,      # background color
	$off,      # background color
	$palette_file, # where to save selections


	### A separate box for entering IAM (and other) commands
	$iam_label,
	$iam_text,
	$iam, # variable for text entry
	$iam_execute,
	$iam_error, # unused

	# add track gui
	#
	$build_track_label,
	$build_track_text,
	$build_track_add_mono,
	$build_track_add_stereo,
	$build_track_rec_label,
	$build_track_rec_text,
	$build_track_mon_label,
	$build_track_mon_text,

	$build_new_take,

	# transport controls
	
	$transport_label,
	$transport_setup_and_connect,
	$transport_setup, # unused
	$transport_connect, # unused
	$transport_disconnect,
	$transport_new,
	$transport_start,
	$transport_stop,

	$old_bg, # initial background color.
	$old_abg, # initial active background color

	$sn_save_text,# text entry widget
	$sn_save,	# button to save settings
	$sn_recall,	# button to recall settings

# end
 

	$saved_version,
	$cop_id,
	%cops,
	%copp,
	%copp_exp,
	$unit,
	%oid_status,
	@tracks_data,
	@bus_data,
	@groups_data,
	@marks_data,
	@fade_data,
	@edit_data,
	@inserts_data,
	@loop_endpoints,
	$loop_enable,
	$length,
	%bunch,
	@command_history,
	$mastering_mode,
	$main_out,
	%old_vol,
	$this_track_name,
	$this_op,
	%devices,
	$alsa_playback_device,
	$alsa_capture_device,
	$soundcard_channels,
	%abbreviations,
	$mix_to_disk_format,
	$raw_to_disk_format,
	$cache_to_disk_format,
	$mixer_out_format,
	$ladspa_sample_rate,
	$ecasound_tcp_port,
	$ecasound_globals_realtime,
	$ecasound_globals_default,
	$project_root,
	$use_group_numbering,
	$press_space_to_start_transport,
	$execute_on_project_load,
	$initial_user_mode,
	$autosave_interval,
	$midish_enable,
	$quietly_remove_tracks,
	$use_jack_plumbing,
	$jack_seek_delay,
	$use_monitor_version_for_mixdown,
	$volume_control_operator,
	$mastering_effects,
	$eq,
	$low_pass,
	$mid_pass,
	$high_pass,
	$compressor,
	$spatialiser,
	$limiter,
	@effects,
	%effect_i,
	%effect_j,
	@effects_help,
	@ladspa_sorted,
	%effects_ladspa,
	%effects_ladspa_file,
	%ladspa_unique_id,
	%ladspa_label,
	%ladspa_help,
	%e_bound,


);


@config_vars = qw(
	%devices
	$alsa_playback_device
	$alsa_capture_device	
	$soundcard_channels
	%abbreviations
	$mix_to_disk_format
	$raw_to_disk_format
	$cache_to_disk_format
	$mixer_out_format
	$ladspa_sample_rate 	
	$ecasound_tcp_port
	$ecasound_globals_realtime
	$ecasound_globals_default
	$project_root 	
	$use_group_numbering
	$press_space_to_start_transport
	$execute_on_project_load
	$initial_user_mode
	$autosave_interval
	$midish_enable
	$quietly_remove_tracks
	$use_jack_plumbing
	$jack_seek_delay
	$use_monitor_version_for_mixdown 
	$volume_control_operator
	$mastering_effects
	$eq 
	$low_pass
	$mid_pass
	$high_pass
	$compressor
	$spatialiser
	$limiter
);
@persistent_vars = qw(
	$saved_version 	
	$cop_id 		
	%cops			
	%copp			
	%copp_exp      	
	$unit			
	%oid_status    	
	@tracks_data
	@bus_data
	@groups_data
	@marks_data
	@fade_data
	@edit_data
	@inserts_data
	@loop_endpoints 
	$loop_enable 	
	$length			
	%bunch			
	@command_history
	$mastering_mode
	$main_out 		
	%old_vol		
	$this_track_name 
	$this_op      	
);
@effects_static_vars = qw(
	@effects		
	%effect_i		
	%effect_j      
	@effects_help  
	@ladspa_sorted 
	%effects_ladspa 
	%effects_ladspa_file 
	%ladspa_unique_id 
	%ladspa_label  
	%ladspa_help   
	%e_bound		
);


$text_wrap = new Text::Format {
	columns 		=> 75,
	firstIndent 	=> 0,
	bodyIndent		=> 0,
	tabstop			=> 4,
};

$debug2 = 0; # subroutine names
$debug = 0; # debug statements

$banner = <<BANNER;
      ////////////////////////////////////////////////////////////////////
     /                                                                  /
    /    Nama multitrack recorder v. $VERSION (c)2008-2011 Joel Roth     /
   /                                                                  /
  /    Audio processing by Ecasound, courtesy of Kai Vehmanen        /
 /                                                                  /
////////////////////////////////////////////////////////////////////

BANNER


# other initializations

$unit = 1;
$effects_cache_file = '.effects_cache';
$palette_file = 'palette.yml';
$state_store_file = 'State.yml';
$effect_chain_file = 'effect_chains.yml';
$effect_profile_file = 'effect_profiles.yml';
$chain_setup_file = 'Setup.ecs'; # For loading by Ecasound
$soundcard_channels = 10;
$use_monitor_version_for_mixdown = 1; # not implemented yet
$project_root = join_path( $ENV{HOME}, "nama");
$seek_delay = 0.1; # seconds
$prompt = "nama ('h' for help)> ";
$use_pager = 1;
$use_placeholders = 1;
$save_id = "State";
$user_customization_file = "custom.pl";
$fade_time = 0.3; # when starting/stopping transport
$old_snapshot = {};
$main_out = 1; # enable main output
$this_bus = 'Main';
jack_update(); # to be polled by Event
$memoize = 1;
$volume_control_operator = 'ea'; # default to linear scale
%mute_level 	= (ea => 0, 	eadb => -96); 
%fade_out_level = (ea => 0, 	eadb => -40);
%unity_level 	= (ea => 100, 	eadb => 0); 
$fade_resolution = 200; # steps per second
$default_fade_length = 0.5; # for fade-in, fade-out
$edit_playback_end_margin = 3;
$edit_crossfade_time = 0.03; # 
$Audio::Nama::Fade::fade_down_fraction = 0.75;
$Audio::Nama::Fade::fade_time1_fraction = 0.9;
$Audio::Nama::Fade::fade_time2_fraction = 0.1;
$Audio::Nama::Fade::fader_op = 'ea';

@mastering_track_names = qw(Eq Low Mid High Boost);
$mastering_mode = 0;

init_memoize() if $memoize;

# aliases for concise access

*bn = \%Audio::Nama::Bus::by_name;
*tn = \%Audio::Nama::Track::by_name;
*ti = \%Audio::Nama::Track::by_index;
# $ti{3}->rw
sub setup_grammar { 
}
	### COMMAND LINE PARSER 

	$debug2 and print "Reading grammar\n";

	*commands_yml = __PACKAGE__->section_data("commands_yml");
	$commands_yml = quote_yaml_scalars($commands_yml);
	*cop_hints_yml = __PACKAGE__->section_data("chain_op_hints_yml");
	%commands = %{ Audio::Nama::yaml_in( $Audio::Nama::commands_yml) };

	$Audio::Nama::AUTOSTUB = 1;
	$Audio::Nama::RD_TRACE = 1;
	$Audio::Nama::RD_ERRORS = 1; # Make sure the parser dies when it encounters an error
	$Audio::Nama::RD_WARN   = 1; # Enable warnings. This will warn on unused rules &c.
	$Audio::Nama::RD_HINT   = 1; # Give out hints to help fix problems.

	*grammar = __PACKAGE__->section_data("grammar");

	$parser = Parse::RecDescent->new($grammar) or croak "Bad grammar!\n";

	@help_topic = qw( all
                    project
                    track
                    chain_setup
                    transport
                    marks
                    effects
                    group
                    bus
                    mixdown
                    prompt 
                    diagnostics
					fades
					edits

                ) ;

%help_topic = (

help => <<HELP,
   help <command>          - show help for <command>
   help <fragment>         - show help for commands matching /<fragment>/
   help <ladspa_id>        - invoke analyseplugin for info on a LADSPA id
   help <topic_number>     - list commands under <topic_number> 
   help <topic_name>       - list commands under <topic_name> (lower case)
   help yml                - browse command source file
HELP

project => <<PROJECT,
   load_project, load        - load an existing project 
   project_name, name          - show the current project name
   create_project, create    - create a new project directory tree 
   list_projects, lp         - list all Nama projects
   get_state, recall, retrieve, restore  - retrieve saved settings
   save_state, keep, save    - save project settings to disk
   memoize                   - enable WAV directory cache (default OFF)
   unmemoize                 - disable WAV directory cache
   exit, quit                - exit program, saving state 
PROJECT

chain_setup => <<SETUP,
   arm                       - generate and connect chain setup    
   show_setup, show          - show status, all tracks
   show_chain_setup, chains  - show Ecasound Setup.ecs file
   generate, gen             - generate chainsetup for audio processing
      (usually not necessary)
   connect, con              - connect chainsetup (usually not necessary)
   disconnect, dcon          - disconnect chainsetup (usually not necessary)
SETUP

track => <<TRACK,
   Most of the Track related commands operate on the 'current
   track'. To cut volume for a track called 'sax',  you enter
   'sax mute' or 'sax; mute'. The first part of the
   command sets a new current track. You can also specify a
   current track by number,  i.e.  '4 mute'.

   add_track, add            -  create one or more new tracks
                                example: add sax; r 3 
                                    (record sax from input 3) 
                                example: add piano; r synth
                                    (record piano from JACK client "synth") 

   link_track, link          -  create a new, read-only track that uses audio
                                files from an existing track. 

                                example: link_track new_piano piano
                                example: link_track intro Mixdown my_song_intro 

   import_audio, import      - import a WAV file, resampling if necessary

   remove_track              - remove effects, parameters and GUI for current
                               track

   show_tracks, show, tracks -  show status of all tracks
                                and group settings

   show_track, sh            -  show status of current track,
                                including effects, versions, 
                                modifiers,  "sax; sh"

   show_bus_tracks, shb      -  show status of current bus,
                                mix track and member tracks

   show_tracks_all showa sha - show all tracks, including hidden

   stereo                    -  set track width to 2 channels

   mono                      -  set track width to 1 channel

   solo                      -  mute all tracks but current track

   all, nosolo               -  return to pre-solo status

 - track inputs and outputs 

   source, src, r            -  set track source
                             -  with no arguments returns current signal source

    ----------------------------------------------------------
	for this input              use this command
    ----------------------------------------------------------

     * soundcard channel 3      source 3 

     * JACK client              source fluidsynth
     
     * JACK port                source fluidsynth:left
  
     * JACK port with spaces    source "MPlayer [20120]:out_0"
 
     * unconnected JACK port    source manual (or 'man')
     
       note: the port for mono track 'piano' would be ecasound:piano_in_1

     * JACK ports list          source drum.ports (ports list from drums.ports)
                                source ports  (ports list from trackname.ports)
    -----------------------------------------------------------

   send, out, m, aux         -  create an auxiliary send
                             -  same arguments as 'source'
                             -  currently one send allowed per track
 - version 

   set_version, version, ver, n  -  set current track version

   list_version, lver, lv        - list version numbers of current track

 - rw_status

   rec                     -  set track to REC  
   mon                     -  set track to MON
   off, z                  -  set track OFF (omit from setup)
   rec_defeat, rd          -  toggle track WAV recording on/off

 - vol/pan 

   pan, p                  -  get/set pan position
   pan_back, pb            -  restore pan after pr/pl/pc  
   pan_center, pc          -  set pan center    
   pan_left, pl            -  pan track fully left    
   pan_right, pr           -  pan track fully right    
   unity                   -  unity volume    
   vol, v                  -  get/set track volume    
                              sax vol + 20 (increase by 20)
                              sax vol - 20 (reduce by 20)
                              sax vol * 3  (multiply by 3)
                              sax vol / 2  (cut by half) 
   mute, c, cut            -  mute volume 
   unmute, uncut, cc       -  restore muted volume

 - chain object modifiers

   mod, mods, modifiers    - show or assign select/reverse/playat modifiers
                             for current track
   nomod, nomods, 
   nomodifiers             - remove all modifiers from current track

 - signal processing

   ecanormalize, normalize, norm 
                           - run ecanormalize on current track version
   ecafixdc, fixdc         - run ecafixdc on current track version
   autofix_tracks, autofix - fixdc and normalize selected versions of all MON
                             tracks

 - cutting and time shifting

   set_region,    srg      - specify a track region using times or mark names
   new_region,    nrg      - define a region creating an auxiliary track
   remove_region, rrg      - remove auxiliary track or region definition
   shift_track,   shift    - set playback delay for track/region
   unshift_track, unshift  - eliminate playback delay for track/region

- track caching (intermediate mixdown)

   cache_track,   cache,   ct  - store effects-processed track signal as new version
   uncache_track, uncache, unc - select uncached track version, replace effects

 - hazardous commands for advanced users

   set_track               - directly set current track parameters

   destroy_current_wav     - unlink current track's selected WAV version.
                             Destructive command! USE WITH CARE!!

TRACK

transport => <<TRANSPORT,
   start, t, SPACE    -  Start processing. SPACE must be at beginning of 
                         command line.
   stop, s, SPACE     -  Stop processing. SPACE must be at beginning of 
                         command line.
   rewind, rw         -  Rewind  some number of seconds, i.e. rw 15
   forward, fw        -  Forward some number of seconds, i.e. fw 75
   setpos, sp         -  Set the playback head position, i.e. setpos 49.2
   getpos, gp         -  Get the current head position 
   to_start, beg      - set playback head to start
   to_end, end        - set playback head to end

   loop_enable, loop  -  loop playback between two points
                         example: loop 5.0 200.0 (positions in seconds)
                         example: loop start end (mark names)
                         example: loop 3 4       (mark numbers)
   loop_disable, noloop, nl
                      -  disable looping

   preview            -  start engine with WAV recording disabled
                         (for mic check, etc.) Release with 'arm'.

   doodle             -  start engine with all live inputs enabled.
                         Release with 'preview' or 'arm'.
                         
   ecasound_start, T  - ecasound-only start (not usually needed)

   ecasound_stop, S   - ecasound-only stop (not usually needed)


TRANSPORT

marks => <<MARKS,
   new_mark,      mark, k     - drop mark at current position, with optional name
   list_marks,    lmk,  lm    - list marks showing index, time, name
   next_mark,     nmk,  nm    - jump to next mark 
   previous_mark, pmk,  pm    - jump to previous mark 
   name_mark,           nom   - give a name to current mark 
   to_mark,       tmk,  tom   - jump to a mark by name or index
   remove_mark,   rmk,  rom   - remove current mark
   modify_mark, move_mark, 
    mmk, mm                   - change the time setting of current mark
MARKS

effects => <<EFFECTS,
    
 - information commands

   ladspa_register, lrg       - list LADSPA effects
   preset_register, prg       - list Ecasound presets
   ctrl_register,   crg       - list Ecasound controllers 
   find_effect,     fe        - list available effects matching arguments
                                example: find_effect reverb
   help_effect, he            - full information about an effect 
                                example: help_effect 1209 
                                  (information about LADSPA plugin 1209)
                                example: help_effect valve
                                  (information about LADSPA plugin valve)

 - effect manipulation commands

   add_effect,     afx        - add an effect to the current track
   add_controller, acl        - add an Ecasound controller
   insert_effect,  ifx        - insert an effect before another effect
   modify_effect,  mfx,
     modify_controller, mcl   - set, increment or decrement effect parameter
   remove_effect, rfx         
     remove_controller, rcl   - remove an effect or controller
   append_effect              - add effect to the end of current track
                                effect list 

-  send/receive inserts

   add_insert,         ain    - add an insert to current track
   remove_insert,      rin    - remove an insert from current track
   set_insert_wetness, wet    - set/query insert wetness 
                                example: wet 99 (99% wet, 1% dry)

-  effect chains (presets, each consisting of multiple effects)

   new_effect_chain, nec         - define a new effect chain
   add_effect_chain, aec         - add an effect chain to the current track
   delete_effect_chain, dec      - delete an effect chain
   list_effect_chains, lec       - list effect chains and their parameters
   bypass_effects, bypass, bye   - suspend current track effects except vol/pan
   restore_effects, restore, ref - restore track effects

-  effect profiles (effect chains for a group of tracks)

   new_effect_profile, nep       - define a new effect profile
   apply_effect_profile, aep     - apply an effect profile
                                   (current effects are bypassed)
   overlay_effect_profile, oep   - apply an effect profile,
                                   adding to current effects
   delete_effect_profile, dep    - delete an effect profile definition

EFFECTS

group => <<GROUP,
   group_rec, grec, R         - group REC mode 
   group_mon, gmon, M         - group MON mode 
   group_off, goff, Z         - group OFF mode 
   group_version, gver, gv    - select default group version 
                              - used for switching among 
                                several multitrack recordings
   new_bunch, bunch, nb       - name a bunch of tracks
                                e.g. bunch strings violins cello bass
                                e.g. bunch 3 4 6 7 (track indexes)
   list_bunches,     lb       - list groups of tracks (bunches)
   remove_bunches,   rb       - remove bunch definitions

   for                   - execute commands on several tracks 
                           by name, or by specifying a group or bunch
                           example: for strings; vol +10
                           example: for drumkit congas; mute
                           example: for 3 5; vol * 1.5
                           example: for Main; version 5;; show
                            (operates on all tracks in bus Main,
                            commands following ';;' execute only once)
                           example: for bus; version 5
                            (operates on tracks in current bus)
                           example: for rec; off
                            (operates on tracks in current bus set to 'rec')
                           example: for OFF; off
                            (operates on tracks in current bus w/status 'OFF')
GROUP

bus => <<BUS,
   add_send_bus_raw,    asbr  - create bus and slave tracks for 
                                sending pre-fader track signals
   add_send_bus_cooked, asbc  - as above, for post-fader signals
   update_send_bus,     usb   - refresh send bus track list
   remove_bus,                - remove a bus
   add_sub_bus,         asub  - create a sub-bus feeding a regular user track
                                of the same name
                                example: add_sub_bus Strings 
                                         add_tracks violin cello bass
                                         for cello violin bass; move_to_bus Strings

BUS

mixdown => <<MIXDOWN,
   mixdown,    mxd             - enable mixdown 
   mixoff,     mxo             - disable mixdown 
   mixplay,    mxp             - playback a recorded mix 
   automix                     - normalize track vol levels, then mixdown
   master_on,  mr              - enter mastering mode
   master_off, mro             - leave mastering mode
MIXDOWN

prompt => <<PROMPT,
   At the command prompt, you can enter several types
   of commands:

   Type                        Example
   ------------------------------------------------------------
   Nama commands               load somesong
   Ecasound commands           cs-is-valid
   Shell expressions           ! ls
   Perl code                   eval 2*3     # prints '6'

PROMPT

diagnostics => <<DIAGNOSTICS,

   dump_all,   dumpall,   dumpa - dump most internal state
   dump_track, dumpt,     dump  - dump current track data
   dump_group, dumpgroup, dumpg - dump group settings for user tracks
   show_io,    showio           - show chain inputs and outputs
   engine_status, egs           - display ecasound audio processing engine
                                   status
DIAGNOSTICS

edits => <<EDITS,

-  general

   list_edits,       led        - list edits
   new_edit,         ned        - create new edit for current track and version
   select_edit,      sed        - choose an edit to modify, becomes current edit
   end_edit_mode,    eem        - track plays full length
   disable_edits,    ded        - disable edits for current track
   destroy_edit                 - remove all WAV files and data for current edit
   
-  edit marks

   set_edit_points,  sep        - mark play start, rec start and rec end 

   play_start_mark,  psm        - select and move to play start mark
   rec_start_mark,   rsm        - select and move to rec start mark
   red_end_mark,     rem        - select and move to rec end mark

   set_play_start_mark, spsm    - set mark to current position
   set_rec_start_mark,  srsm    - set mark to current position
   set_rec_end_mark,    srem    - set mark to current position

-  preview edit segment

   preview_edit_in   pei        - preview track with edit segment removed
   preview_edit_out  peo        - preview edit segment to be removed

-  record/play edit

   record_edit       red        - record a WAV file for current edit
   play_edit         ped        - play a completed edit

-  select edit related tracks

   edit_track,       et         - set edit track as current track
   edit_track,       et         - set edit track as current track
   host_track,       ht         - set host track alias as current track
   host_track_alias, hta        - set host track alias as current track
   version_mix_track,vmt        - set version mix track as current track 
EDITS

fades => <<FADES,
   add_fade,         afd, fade  - add fade (in or out) to current track
                                  examples: 
                                      fade in song_start 0.2
                                  (fades in at mark 'song_start' over 0.2 s)
                                      fade out 0.5 song_start
                                  (fades out over 0.5 s ending at 'song_start')
                                  
   remove_fade,      rfd        - remove fade (by index)
   list_fade         lfd        - list all fades
FADES
   
);
# print values %help_topic;

$help_screen = <<HELP;

Welcome to Nama help

The help command ('help', 'h') can take several arguments.

help <command>          - show help for <command>
help <fragment>         - show help for all commands matching /<fragment>/
help <topic_number>     - list commands under topic <topic_number> below
help yml                - browse the YAML command source

help is available for the following topics:

0  All
1  Project
2  Track
3  Chain setup
4  Transport
5  Marks
6  Effects
7  Group control
8  Buses
9  Mixdown
10 Command prompt 
11 Diagnostics
12 Edits
13 Fades
HELP


	# we use the following settings if we can't find config files

	*default = __PACKAGE__->section_data("default_namarc");

	# default user customization file custom.pl - see EOF
	
	*custom_pl = __PACKAGE__->section_data("custom_pl");

	# default colors

	*default_palette_yml = __PACKAGE__->section_data("default_palette_yml");

	# JACK environment for testing

	*fake_jack_lsp = __PACKAGE__->section_data("fake_jack_lsp");

	# Midish command keywords
	
	%midish_command = map{ $_, 1} split " ", 
		${ __PACKAGE__->section_data("midish_commands") };

	# print remove_spaces("bulwinkle is a...");

#### Class and Object definitions for package 'Audio::Nama'

our @ISA; # no anscestors
use Audio::Nama::Object qw(mode);

## The following methods belong to the root class

sub hello {"superclass hello"}

sub new { my $class = shift; return bless {@_}, $class }

sub main { 
#	setup_grammar(); 		# executes directly in body
	process_options(); 		# Option_subs.pm
	initialize_interfaces();# Initialize_subs.pm
	command_process($execute_on_project_load);
	reconfigure_engine();	# Engine_setup_subs.pm
	command_process($opts{X});
	$ui->loop;
}

## User Customization -- called by initialize_interfaces()
#  we leave it here because it needs access to all global variables

sub setup_user_customization {
	my $file = user_customization_file();
	return unless -r $file;
	say "reading user customization file $user_customization_file";
	my @return;
	unless (@return = do $file) {
		say "couldn't parse $file: $@\n" if $@;
		return;
	}
	# convert key-value pairs to hash
	$debug and print join "\n",@return;
	my %custom = @return ; 
	my $prompt;
	$prompt = gen_coderef('prompt', $custom{prompt}) if $custom{prompt};
	{ no warnings 'redefine';
		*prompt = $prompt if $prompt;
	}
	my @commands = keys %{ $custom{commands} };
	for my $cmd(@commands){
		my $coderef = gen_coderef($cmd,$custom{commands}{$cmd}) or next;
		$user_command{$cmd} = $coderef;
	}
	%user_alias   = %{ $custom{aliases}  };
}
sub user_customization_file { join_path(project_root(),$user_customization_file) }

sub gen_coderef {
	my ($cmd,$code) = @_;
	my $coderef = eval "sub{ use feature ':5.10'; $code }";
	say("couldn't parse command $cmd: $@"), return if $@;
	$coderef
}

# called from grammar

sub do_user_command {
	#say "args: @_";
	my($cmd, @args) = @_;
	$user_command{$cmd}->(@args);
}	

sub do_script {

	my $name = shift;
	my $file;
	# look in project_dir() and project_root()
	# if filename provided does not contain slash
	if( $name =~ m!/!){ $file = $name }
	else {
		$file = join_path(project_dir(),$name);
		if(-e $file){}
		else{ $file = join_path(project_root(),$name) }
	}
	-e $file or say("$file: file not found. Skipping"), return;
	my @lines = split "\n",read_file($file);
	my $old_opt_r = $opts{R};
	$opts{R} = 1; # turn off auto reconfigure
	for my $input (@lines) { process_line($input)};
	$opts{R} = $old_opt_r;
}

sub dump_all {
	my $tmp = ".dump_all";
	my $fname = join_path( project_root(), $tmp);
	save_state($fname);
	file_pager("$fname.yml");
}


sub leading_track_spec {
	my $cmd = shift;
	if( my $track = $tn{$cmd} || $ti{$cmd} ){
		$debug and print "Selecting track ",$track->name,"\n";
		$this_track = $track;
		set_current_bus();
		ecasound_select_chain( $this_track->n );
		1;
	}
		
}
sub eval_perl {
	my $code = shift;
	my (@result) = eval $code;
	print( "Perl command failed: $@\n") if $@;
	pager(join "\n", @result) unless $@;
	print "\n";
}	
sub import_audio {

	my ($track, $path, $frequency) = @_;
	
	$track->import_audio($path, $frequency);

	# check that track is audible
	
	my $bus = $bn{$track->group};

	# set MON status unless track _is_ audible
	
	$track->set(rw => 'MON') 
		unless $bus->rw eq 'MON' and $track->rw eq 'REC';

	# warn if bus is OFF
	
	print("You must set bus to MON (i.e. \"bus_mon\") to hear this track.\n") 
		if $bus->rw eq 'OFF';
}
sub destroy_current_wav {
	my $old_group_status = $main->rw;
	$main->set(rw => 'MON');
	$this_track->current_version or
		say($this_track->name, 
			": No current version (track set to OFF?) Skipping."), return;
	my $wav = $this_track->full_path;
	my $reply = $term->readline("delete WAV file $wav? [n] ");
	#my $reply = chr($term->read_key()); 
	if ( $reply =~ /y/i ){
		# remove version comments, if any
		delete $this_track->{version_comment}{$this_track->current_version};
		print "Unlinking.\n";
		unlink $wav or warn "couldn't unlink $wav: $!\n";
		rememoize();
	}
	$term->remove_history($term->where_history);
	$main->set(rw => $old_group_status);
	1;
}


sub is_bunch {
	my $name = shift;
	$bn{$name} or $bunch{$name}
}

sub pan_check {
	my $new_position = shift;
	my $current = $copp{ $this_track->pan }->[0];
	$this_track->set(old_pan_level => $current)
		unless defined $this_track->old_pan_level;
	effect_update_copp_set(
		$this_track->pan,	# id
		0, 					# parameter
		$new_position,		# value
	);
}

# called from grammar_body.pl, Mute_Solo_Fade, Effect_chain_subs
{
my %set_stat = ( 
				 (map{ $_ => 'rw' } qw(rec mon off) ), 
				 map{ $_ => 'rec_status' } qw(REC MON OFF)
				 );

sub bunch_tracks {
	my $bunchy = shift;
	my @tracks;
	if ( my $bus = $bn{$bunchy}){
		@tracks = $bus->tracks;
	} elsif ( $bunchy eq 'bus' ){
		$debug and print "special bunch: bus\n";
		@tracks = grep{ ! $bn{$_} } $bn{$this_bus}->tracks;
	} elsif ($bunchy =~ /\s/  # multiple identifiers
		or $tn{$bunchy} 
		or $bunchy !~ /\D/ and $ti{$bunchy}){ 
			$debug and print "multiple tracks found\n";
			# verify all tracks are correctly named
			my @track_ids = split " ", $bunchy;
			my @illegal = grep{ ! track_from_name_or_index($_) } @track_ids;
			if ( @illegal ){
				say("Invalid track ids: @illegal.  Skipping.");
			} else { @tracks = map{ $_->name} 
							   map{ track_from_name_or_index($_)} @track_ids; }

	} elsif ( my $method = $set_stat{$bunchy} ){
		$debug and say "special bunch: $bunchy, method: $method";
		$bunchy = uc $bunchy;
		@tracks = grep{$tn{$_}->$method eq $bunchy} 
				$bn{$this_bus}->tracks
	} elsif ( $bunch{$bunchy} and @tracks = @{$bunch{$bunchy}}  ) {
		$debug and print "bunch tracks: @tracks\n";
	} else { say "$bunchy: no matching bunch identifier found" }
	@tracks;
}
}
sub track_from_name_or_index { /\D/ ? $tn{$_[0]} : $ti{$_[0]}  }

# called from almost everywhere

sub command_process {
	my $input = shift;
	my $input_was = $input;

	# parse repeatedly until all input is consumed
	
	while ($input =~ /\S/) { 
		$debug and say "input: $input";
		$parser->meta(\$input) or print("bad command: $input_was\n"), last;
	}
	$ui->refresh; # in case we have a graphic environment
	set_current_bus();
}
	
## called from ChainSetup.pm and Engine_setup_subs.pm

sub setup_file { join_path( project_dir(), $chain_setup_file) };

## called from 
# Track_subs
# Graphical_subs
# Refresh_subs
# Core_subs
# Realtime_subs

# vol/pan requirements of mastering and mixdown tracks

# called from Track_subs, Graphical_subs
{ my %volpan = (
	Eq => {},
	Low => {},
	Mid => {},
	High => {},
	Boost => {vol => 1},
	Mixdown => {},
);

sub need_vol_pan {

	# this routine used by 
	#
	# + add_track() to determine whether a new track _will_ need vol/pan controls
	# + add_track_gui() to determine whether an existing track needs vol/pan  
	
	my ($track_name, $type) = @_;

	# $type: vol | pan
	
	# Case 1: track already exists
	
	return 1 if $tn{$track_name} and $tn{$track_name}->$type;

	# Case 2: track not yet created

	if( $volpan{$track_name} ){
		return($volpan{$track_name}{$type}	? 1 : 0 )
	}
	return 1;
}
}

# track width in words
# called from grammar_body.pl,Track.pm

sub width {
	my $count = shift;
	return 'mono' if $count == 1;
	return 'stereo' if $count == 2;
	return "$count channels";
}

sub cleanup_exit {
 	remove_riff_header_stubs();
	# for each process: 
	# - SIGINT (1st time)
	# - allow time to close down
	# - SIGINT (2nd time)
	# - allow time to close down
	# - SIGKILL
	map{ my $pid = $_; 
		 map{ my $signal = $_; 
			  kill $signal, $pid; 
			  sleeper(0.2) 
			} (2,2,9)
	} @ecasound_pids;
 	#kill 15, ecasound_pid() if $sock;  	
	close_midish() if $midish_enable;
	$term->rl_deprep_terminal() if defined $term;
	exit; 
}
END { cleanup_exit() }

# TODO

sub list_plugins {}
		
sub show_tracks_limited {

	# Master
	# Mixdown
	# Main bus
	# Current bus

}
sub process_control_inputs { }

### end Core_subs



package Audio::Nama;  # for Data::Section


1;
__DATA__
__[commands_yml]__
---
help:
  what: display help 
  short: h
  parameters: [ <i_help_topic_index> | <s_help_topic_name> | <s_command_name> ]
  type: help 
help_effect:
  type: help
  short: hfx he
  parameters: <s_label> | <i_unique_id>
  what: display analyseplugin output if available or one-line help
find_effect:
  type: help 
  short: ffx fe
  what: display one-line help for effects matching search strings
  parameters: <s_keyword1> [ <s_keyword2>... ]
exit:
  short: quit q
  what: exit program, saving settings
  type: general
  parameters: none
memoize:
  type: general
  what: enable WAV dir cache
  parameters: none
unmemoize:
  type: general
  what: disable WAV dir cache
  parameters: none
stop:
  type: transport
  short: s
  what: stop transport
  parameters: none
start:
  type: transport
  short: t
  what: start transport
  parameters: none
getpos:
  type: transport
  short: gp
  what: get current playhead position (seconds)
  parameters: none
setpos:
  short: sp
  what: set current playhead position
  example: setpos 65 (set play position to 65 seconds from start)
  parameters: <f_position_seconds>
  type: transport
forward:
  short: fw
  what: move playback position forward
  parameters: <f_increment_seconds>
  type: transport
rewind:
  short: rw
  what: move transport position backward
  parameters: <f_increment_seconds>
  type: transport
to_start:
  what: set playback head to start
  type: transport
  short: beg
  parameters: none
to_end:
  what: set playback head to end minus 10 seconds 
  short: end
  type: transport
  parameters: none
ecasound_start:
  type: transport
  short: T
  what: ecasound-only start
  parameters: none
ecasound_stop:
  type: transport
  short: S
  what: ecasound-only stop
  parameters: none
preview:
  type: transport
  what: start engine with rec_file disabled (for mic test, etc.)
  parameters: none
doodle:
  type: transport
  what: start engine while monitoring REC-enabled inputs
  parameters: none
mixdown:
  type: mix
  short: mxd
  what: enable mixdown for subsequent engine runs
  parameters: none
mixplay:
  type: mix
  short: mxp
  what: Enable mixdown file playback, setting user tracks to OFF
  parameters: none
mixoff:
  type: mix
  short: mxo
  what: Set Mixdown track to OFF, user tracks to MON
  parameters: none
automix:
  type: mix
  what: Normalize track vol levels, then mixdown
  parameters: none
master_on:
  type: mix
  short: mr
  what: Enter mastering mode. Add tracks Eq, Low, Mid, High and Boost if necessary
  parameters: none
master_off:
  type: mix
  short: mro
  what: Leave mastering mode
  parameters: none
main_off:
  type: general
  what: turn off main output
  parameters: none
main_on:
  type: general
  what: turn on main output
  parameters: none
add_track:
  type: track
  short: add new
  what: create a new track
  example: add_track clarinet group woodwinds
  parameters: <s_name> [ <s_key1> <s_val1> <s_key2> <s_val2>... ]
add_tracks:
  type: track
  short: add new
  what: create one or more new tracks
  example: add_track sax violin tuba
  parameters: <s_name1> [ <s_name2>... ]
link_track:
  type: track
  short: link
  what: create a read-only track that uses .WAV files from another track. 
  parameters: <s_name> <s_target> [ <s_project> ]
  example: link_track intro Mixdown song_intro creates a track 'intro' using all .WAV versions from the Mixdown track of 'song_intro' project
import_audio:
  type: track
  short: import
  what: import a sound file (wav, ogg, mp3, etc.) to the current track, resampling if necessary.
  parameters: <s_wav_file_path> [i_frequency]
set_track:
  type: track
  what: directly set current track parameters (use with care!)
  parameters: <s_track_field> value
rec:
  type: track
  what: REC-enable current track
  parameters: none
mon:
  type: track
  short: on
  what: set current track to MON
  parameters: none
off:
  type: track
  short: z
  what: set current track to OFF (exclude from chain setup)
  parameters: none
rec_defeat:
  type: track
  short: rd
  what: prevent writing a WAV file for current track
  parameters: none
rec_enable:
  type: track
  short: re
  what: allow writing a WAV file for current track
  parameters: none
source:
  type: track
  what: set track source
  short: src r
  parameters: <i_soundcard_channel> | 'null' (for metronome) | <s_jack_client_name> | <s_jack_port_name> | 'jack' (opens ports ecasound:trackname_in_N, connects ports listed in trackname.ports if present in project_root dir)
  example: source "MPlayer [20120]:out_0" 
send:
  type: track
  what: set aux send
  short: out aux
  parameters: <i_soundcard_channel> (3 or above) | <s_jack_client_name>
remove_send:
  type: track
  short: nosend rms
  what: remove aux send
  parameters: none
stereo:
  type: track
  what: record two channels for current track
  parameters: none
mono:
  type: track
  what: record one channel for current track
  parameters: none
set_version:
  type: track
  short: version n ver
  what: set track version number for monitoring (overrides group version setting)
  parameters: <i_version_number>
  example: sax; version 5; sh
destroy_current_wav:
  type: track
  what: unlink current track's selected WAV version (use with care!)
  parameters: none
list_versions:
  type: track
  short: lver lv
  what: list version numbers of current track
  parameters: none
vol:
  type: track
  short: v
  what: set, modify or show current track volume
  parameters: [ [ + | - | * | / ] <f_value> ]
  example: vol * 1.5 (multiply current volume setting by 1.5)
mute:
  type: track
  short: c cut
  what: mute current track volume
  parameters: none
unmute:
  type: track
  short: C uncut
  what: restore previous volume level
unity:
  type: track
  what: set current track volume to unity
  parameters: none
solo:
  type: track
  what: mute all but current track
  short: sl
  parameters: [track_name(s)] [bunch_name(s)]
nosolo:
  type: track
  what: release solo, previously muted tracks are still muted
  short: nsl
  parameters: none
all:
  type: track
  what: release solo, unmuting all tracks
  parameters: none
pan:
  type: track
  short: p
  what: get/set current track pan position
  parameters: [ <f_value> ]
pan_right:
  type: track
  short: pr
  what: pan current track fully right
  parameters: none
pan_left:
  type: track
  short: pl
  what: pan current track fully left
  parameters: none
pan_center:
  type: track
  short: pc
  what: set pan center
  parameters: none
pan_back:
  type: track
  short: pb
  what: restore current track pan setting prior to pan_left, pan_right or pan_center
  parameters: none
show_tracks:
  type: track 
  short: show lt
  what: show track status
show_tracks_all:
  type: track
  short: sha showa 
  what: show status of all tracks, visible and hidden
show_bus_tracks:
  type: track 
  short: shb
  what: show tracks in current bus
show_track:
  type: track
  short: sh
  what: show current track status
show_mode:
  type: setup
  short: shm
  what: show current record/playback modes
set_region:
  type: track
  short: srg
  what: Specify a playback region for the current track using marks. Use 'new_region' for multiple regions.
  parameters: <s_start_mark_name> <s_end_mark_name>
new_region:
  type: track
  short: nrg
  what: Create a region for the current track using an auxiliary track 
  parameters: <s_start_mark_name> <s_end_mark_name> [<s_region_name>]
remove_region:
  type: track
  short: rrg
  what: remove region (including associated auxiliary track)
  parameters: none
shift_track:
  type: track
  short: shift playat pat
  what: set playback delay for track or region
  parameters: <s_start_mark_name> | <i_start_mark_index | <f_start_seconds> 
unshift_track:
  type: track
  short: unshift
  what: remove playback delay for track or region
  parameters: none
modifiers:
  type: track
  short: mods mod 
  what: set/show modifiers for current track (man ecasound for details)
  parameters: [ Audio file sequencing parameters ]
  example: modifiers select 5 15.2
nomodifiers:
  type: track
  short: nomods nomod
  what: remove modifiers from current track
normalize:
  type: track
  short: norm ecanormalize
  what: apply ecanormalize to current track version
fixdc:
  type: track
  what: apply ecafixdc to current track version
  short: ecafixdc
autofix_tracks:
  type: track 
  short: autofix
  what: fixdc and normalize selected versions of all MON tracks 
  parameters: none
remove_track:
  type: track
  short:
  what: remove effects, parameters and GUI for current track
  parameters: none 
bus_rec:
  type: bus
  short: brec grec
  what: rec-enable bus tracks
bus_mon:
  type: bus
  short: bmon gmon
  what: set group-mon mode for bus tracks
bus_off:
  type: bus
  short: boff goff
  what: set group-off mode for bus tracks
bus_version:
  type: group 
  short: bn bver bv gver gn gv
  what: set default monitoring version for tracks in current bus
new_bunch:
  type: group
  short: nb
  what: define a bunch of tracks
  parameters: <s_group_name> [<s_track1> <s_track2>...]
list_bunches:
  type: group
  short: lb
  what: list track bunches
  parameters: none
remove_bunches:
  short: rb
  type: group
  what: remove the definition of a track bunch
  parameters: <s_bunch_name> [<s_bunch_name>...]
add_to_bunch:
  short: ab
  type: group
  what: add track(s) to a bunch
  parameters: <s_bunch_name> <s_track1> [<s_track2>...]
save_state:
  type: project
  short: keep save
  what: save project settings to disk
  parameters: [ <s_settings_file> ] 
get_state:
  type: project
  short: recall retrieve
  what: retrieve project settings
  parameters: [ <s_settings_file> ] 
list_projects:
  type: project
  short: lp
  what: list projects
create_project:
  type: project
  short: create
  what: create a new project
  parameters: <s_new_project_name>
load_project:
  type: project
  short: load
  what: load an existing project using last saved state
  parameters: <s_project_name>
project_name:
  type: project
  what: show current project name
  short: project name
  parameters: none
new_project_template:
  type: project
  what: make a project template based on current project
  short: npt
  parameters: <s_template_name> [<s_template_description>]
use_project_template:
  type: project
  what: use a template to create tracks in a newly created, empty project
  short: upt apt
  parameters: <s_template_name>
list_project_templates:
  type: project
  what: list project templates
  short: lpt
remove_project_template:
  type: project
  what: remove one or more project templates
  short: rpt dpt
  parameters: <s_template_name1> [<s_template_name2>... ]
generate:
  type: setup
  short: gen
  what: generate chain setup for audio processing
  parameters: none
arm:
  type: setup
  what: generate and connect chain setup
  parameters: none
connect:
  type: setup
  short: con
  what: connect chain setup
  parameters: none
disconnect:
  type: setup
  short: dcon
  what: disconnect chain setup
  parameters: none
show_chain_setup:
  type: setup
  short: chains
  what: show current Ecasound chain setup
loop_enable:
  type: setup 
  short: loop
  what: loop playback between two points
  parameters: <start> <end> (start, end: mark names, mark indices, decimal seconds)
  example: |
    loop_enable 1.5 10.0  ; loop between 1.5 and 10.0 seconds
    loop_enable 1 5       ; loop between mark indices 1 and 5 
    loop_enable start end ; loop between mark ids 'start' and 'end'
loop_disable:
  type: setup 
  short: noloop nl
  what: disable automatic looping
  parameters: none
add_controller:
  type: effect
  what: add a controller to an operator (use mfx to modify, rfx to remove)
  parameters: <s_parent_id> <s_effect_code> [ <f_param1> <f_param2>...]
  short: acl
add_effect:
  short: afx
  type: effect
  what: add effect to the end of current track
  parameters: <s_effect_code> [ <f_param1> <f_param2>... ]
  example: |2
    add_effect amp 6     ; LADSPA Simple amp 6dB gain
    add_effect var_dali  ; preset var_dali. Note that you don't need
                         ; Ecasound's el: or pn: prefix
insert_effect:
  type: effect
  short: ifx
  what: place effect before specified effect (engine stopped, prior to arm only)
  parameters: <s_insert_point_id> <s_effect_code> [ <f_param1> <f_param2>... ]
modify_effect:
  type: effect
  what: modify an effect parameter
  parameters: <s_effect_id> <i_parameter> [ + | - | * | / ] <f_value>
  short: mfx modify_controller mcl
  example: |
    modify_effect V 1 -1           ; set effect_id V, parameter 1 to -1
    modify_effect V 1 - 10         ; reduce effect_id V, parameter 1 by 10
    modify_effect V 1,2,3 + 0.5    ; modify multiple parameters
    modify_effect V,AC,AD 1,2 3.14 ; set multiple effects/parameters
remove_effect:
  type: effect
  what: remove effects from selected track
  short: rfx remove_controller rcl
  parameters: <s_effect_id1> [ <s_effect_id2>...]
position_effect:
  type: effect
  what: position an effect before another effect (use 'ZZZ' for end)
  short: pfx
  parameters: [<s_effect_id>]
show_effect:
  type: effect
  what: show effect information
  short: sfx
  parameters: <s_effect_id1> [ <s_effect_id2>...]
add_insert:
  type: effect 
  short: ain
  what: add an external send/return to current track
  parameters: ( pre | post ) <s_send_id> [<s_return_id>]
set_insert_wetness:
  type: effect 
  short: wet
  what: set wet/dry balance for current track insert: 100 = all wet, 0 = all dry
  parameters: [ pre | post ] <n_wetness> 
remove_insert:
  type: effect
  short: rin
  what: remove an insert from the current track 
  parameters: [ pre | post ] 
ctrl_register:
  type: effect
  what: list Ecasound controllers
  short: crg
  parameters: none
preset_register:
  type: effect
  what: list Ecasound presets 
  short: prg
  parameters: none
ladspa_register:
  type: effect
  what: list LADSPA plugins
  short: lrg
  parameters: none
list_marks:
  type: mark
  short: lmk lm
  what: List all marks
  parameters: none
to_mark:
  type: mark
  short: tmk tom
  what: move playhead to named mark or mark index
  parameters: <s_mark_id> | <i_mark_index> 
  example: to_mark start (go to mark named 'start')
new_mark:
  type: mark
  what: drop mark at current playback position
  short: mark k
  parameters: [ <s_mark_id> ]
remove_mark:
  type: mark
  what: Remove mark, default to current mark
  short: rmk rom
  parameters: [ <s_mark_id> | <i_mark_index> ]
  example: remove_mark start (remove mark named 'start')
next_mark:
  type: mark
  short: nmk nm
  what: Move playback head to next mark
  parameters: none
previous_mark:
  type: mark
  short: pmk pm
  what: Move playback head to previous mark
  parameters: none
name_mark:
  type: mark
  short: nmk nom
  what: Give a name to the current mark
  parameters: <s_mark_id>
  example: name_mark start
modify_mark:
  type: mark
  short: move_mark mmk mm
  what: change the time setting of current mark
  parameters: [ + | - ] <f_seconds>
engine_status:
  type: diagnostics
  what: display Ecasound audio processing engine status
  short: egs
  parameters: none
dump_track:
  type: diagnostics
  what: dump current track data
  short: dumpt dump
  parameters: none
dump_group:
  type: diagnostics 
  what: dump group settings for user tracks 
  short: dumpgroup dumpg
  parameters: none
dump_all:
  type: diagnostics
  what: dump most internal state
  short: dumpall dumpa
  parameters: none
show_io:
  type: diagnostics
  short: showio
  what: show chain inputs and outputs
  parameters: none
list_history:
  type: help
  short: lh
  what: list command history
  parameters: none
add_send_bus_cooked:
  type: bus
  short: asbc
  what: add a send bus that copies all user tracks' processed signals
  parameters: <s_name> <destination>
  example: asbc Reverb jconv
add_send_bus_raw:
  type: bus
  short: asbr
  what: add a send bus that copies all user tracks' raw signals
  parameters: <s_name> <destination>
  example: asbr Reverb jconv
add_sub_bus:
  type: bus
  short: asub
  what: add a sub bus (default destination: to mixer via eponymous track)
  parameters: <s_name> [destination: s_track_name|s_jack_client|n_soundcard channel]
  example: |
    asub Strings_bus
    asub Strings_bus some_jack_client
update_send_bus:
  type: bus
  short: usb
  what: include tracks added since send bus was created
  parameters: <s_name>
  example: usb Some_bus 
remove_bus:
  type: bus
  short:
  what: remove a bus
  parameters: <s_bus_name>
list_buses:
  type: bus
  short: lbs
  what: list buses and their parameters TODO
  parameters: none
set_bus:
  type: bus
  short: sbs
  what: set bus parameters 
  parameters: <s_busname> <key> <val>
new_effect_chain:
  type: effect
  short: nec
  what: define a reusable sequence of effects (effect chain) with current parameters
  parameters: <s_name> [<op1>, <op2>,...]
add_effect_chain:
  type: effect
  short: aec
  what: add an effect chain to the current track
  parameters: <s_name>
overwrite_effect_chain:
  type: effect
  short: oec
  what: add an effect chain overwriting current effects (which are pushed onto stack)
  parameters: <s_name>
delete_effect_chain:
  type: effect
  short: dec
  what: delete an effect chain definition from the list
  parameters: <s_name>
list_effect_chains:
  type: effect
  short: lec
  what: list effect chains, matching any strings provided
  parameters: [<s_frag1> <s_frag2>... ]
bypass_effects:
  type: effect
  short: bypass bye
  what: bypass track effects (pushing them onto stack) except vol/pan 
  parameters: none
restore_effects:
  type: effect
  short: restore ref 
  what: restore bypassed track effects
new_effect_profile:
  type: effect
  short: nep
  what: create a named group of effect chains for multiple tracks
  parameters: <s_bunch_name> [<s_effect_profile_name>]
apply_effect_profile:
  type: effect
  short: aep
  what: use an effect profile to overwrite effects of multiple tracks
  parameters: <s_effect_profile_name>
overlay_effect_profile:
  type: effect
  short: oep
  what: use an effect profile to add effects to multiple tracks
  parameters: <s_effect_profile_name>
delete_effect_profile:
  type: effect
  short: dep
  what: remove an effect chain bunch definition
  parameters: <s_effect_profile_name>
list_effect_profiles:
  type: effect
  short: lep
  what: list effect chain bunches
cache_track:
  type: track
  short: cache ct
  what: store an effects-processed track signal as a new version
  parameters: [<f_additional_processing_time>]
uncache_track:
  type: effect
  short: uncache unc
  what: select the uncached track version; restores effects (but not inserts)
  parameters: none
do_script:
  type: general
  short: do
  what: execute Nama commands from a file in project_dir or project_root
  parameters: <s_filename>
scan:
  type: general
  what: re-read project's .wav directory
  parameters: none
add_fade:
  type: effect
  short: afd fade
  what: add a fade-in or fade-out to current track
  parameters: in|out marks/times (see examples)
  example: |
    fade in mark1        ; fade in default 0.5s starting at mark1
    fade out mark2 2     ; fade out over 2s starting at mark2
    fade out 2 mark2     ; fade out over 2s ending at mark2
    fade out mark1 mark2 ; fade out from mark1 to mark2
remove_fade:
  type: effect 
  short: rfd
  what: remove a fade from the current track
  parameters: <i_fade_index1> [<i_fade_index2>...]
list_fade:
  type: effect
  short: lfd
  what: list fades
add_comment:
  type: track
  what: add comment to current track (replacing any previous comment)
  short: comment ac
remove_comment:
  type: track
  what: remove comment from current track
  short: rc
show_comment:
  type: track
  what: show comment for current track
  short: sc
show_comments:
  type: track
  what: show all track comments
  short: scs
add_version_comment:
  type: track
  what: add version comment (replacing any previous user comment)
  short: comment avc
remove_version_comment:
  type: track
  what: remove version comment(s) from current track
  short: rvc
show_version_comment:
  type: track
  what: show version comment(s)
  short: svc
show_version_comments_all:
  type: track
  what: show all version comments for current track
  short: svca
set_system_version_comment:
  type: track
  what: set system version comment (for testing only)
  short: comment ssvc 
midish_command:
  type: midi
  what: send command text to 'midish' MIDI sequencer shell
  short: m
  parameters: <s_command_text>
new_edit:
  type: edit
  what: create an edit for the current track and version
  short: ned
  parameters: none
set_edit_points:
  type: edit
  what: mark play-start, record-start and record-end positions
  short: sep
  parameters: none
list_edits:
  type: edit
  what: list edits for current track and version
  short: led
  parameters: none
select_edit:
  type: edit
  what: select an edit to modify or delete, becomes current edit
  short: sed
  parameters: <i_edit_index>
end_edit_mode:
  type: edit
  what: current track plays full length (input from edit sub-bus)
  short: eem
  parameters: none
destroy_edit:
  type: edit
  what: remove an edit and all associated WAV files (destructive)
  parameters: [<i_edit_index>] (defaults to current edit)
preview_edit_in:
  type: edit
  what: play the track region without the edit segment 
  short: pei
  parameters: none
preview_edit_out:
  type: edit
  what: play the removed edit segment
  short: peo
  parameters: none
play_edit:
  type: edit
  what: play a completed edit
  short: ped
  parameters: none
record_edit:
  type: edit
  what: record a WAV file for the current edit
  short: red
  parameters: none
edit_track:
  type: edit
  what: set the edit track as current track
  short: et
  parameters: none
host_track_alias:
  type: edit
  what: set the host track alias as the current track
  short: hta
  parameters: none
host_track:
  type: edit
  what: set the host track (edit sub-bus mix track) as the current track
  short: ht
  parameters: none
version_mix_track:
  type: edit
  what: set the version mix track as the current track
  short: vmt 
  parameters: none
play_start_mark:
  type: edit
  what: select (and move to) play start mark
  short: psm
  parameters: none
rec_start_mark:
  type: edit
  what: select (and move to) rec start mark
  short: rsm
  parameters: none
rec_end_mark:
  type: edit
  what: select (and move to) rec end mark
  short: rem
  parameters: none
set_play_start_mark:
  type: edit
  what: set play_start_mark to current engine position
  short: spsm
  parameters: none
set_rec_start_mark:
  type: edit
  what: set rec_start_mark to current engine position
  short: srsm
  parameters: none
set_rec_end_mark:
  type: edit
  what: set rec_end_mark to current engine position
  short: srem
  parameters: none
disable_edits:
  type: edit
  short: ded
  what: disable editing sub-bus, restore standard track behavior
  parameters: none
merge_edits:
  type: edit
  short: med
  what: mix edits and original into a new host-track WAV version
explode_track:
  type: track
  what: make track into a sub-bus, with one track for each version
move_to_bus:
  type: track
  what: move current track to another bus
  short: mtb
  parameters: <s_bus_name>
promote_version_to_track:
  type: track
  what: create a read-only track using specified version of current track
  short: pvt
  parameters: <i_version_number>
read_user_customizations:
  type: general
  what: re-read user customizations file 'custom.pl'
  short: ruc
limit_run_time:
  type: setup
  what: stop recording after last WAV file finishes playing
  short: lrt
  parameters: [<f_additional_seconds>]
limit_run_time_off:
  type: setup
  what: disable recording stop timer
  short: lro
offset_run:
  type: setup
  short: ofr
  what: record/play from mark position
  parameters: <s_mark_name>  
offset_run_off:
  type: setup
  short: ofo
  what: clear offset run mode
...

__[grammar]__

meta: midish_cmd 
midish_cmd: /[a-z]+/ predicate { 
	return unless $Audio::Nama::midish_command{$item[1]};
	my $line = "$item[1] $item{predicate}";
	Audio::Nama::midish_command($line);
	1;
}
meta: bang shellcode stopper {
	$Audio::Nama::debug and print "Evaluating shell commands!\n";
	my $output = qx( $item{shellcode});
	Audio::Nama::pager($output) if $output;
	print "\n";
	1;
}
meta: eval perlcode stopper {
	$Audio::Nama::debug and print "Evaluating perl code\n";
	Audio::Nama::eval_perl($item{perlcode});
	1;
}
meta: for bunch_spec ';' namacode stopper { 
 	$Audio::Nama::debug and print "namacode: $item{namacode}\n";
 	my @tracks = Audio::Nama::bunch_tracks($item{bunch_spec});
 	for my $t(@tracks) {
 		Audio::Nama::leading_track_spec($t);
		$Audio::Nama::parser->meta($item{namacode});
	}
	1;
}
bunch_spec: text 
meta: nosemi(s /\s*;\s*/) semicolon(?) 
nosemi: text { $Audio::Nama::parser->do_part($item{text}) }
text: /[^;]+/ 
semicolon: ';'
do_part: track_spec command end
do_part: track_spec end
do_part: command end
predicate: nonsemi semistop { $item{nonsemi}}
predicate: /$/
iam_cmd: ident { $item{ident} if $Audio::Nama::iam_cmd{$item{ident}} }
track_spec: ident { Audio::Nama::leading_track_spec($item{ident}) }
bang: '!'
eval: 'eval'
for: 'for'
stopper: ';;' | /$/ 
shellcode: somecode 
perlcode: somecode 
namacode: somecode 
somecode: /.+?(?=;;|$)/ 
nonsemi: /[^;]+/
semistop: /;|$/
command: iam_cmd predicate { 
	my $user_input = "$item{iam_cmd} $item{predicate}"; 
	$Audio::Nama::debug and print "Found Ecasound IAM command: $user_input\n";
	my $result = Audio::Nama::eval_iam($user_input);
	Audio::Nama::pager( $result );  
	1 }
command: user_command predicate {
	Audio::Nama::do_user_command(split " ",$item{predicate});
	1;
}
command: user_alias predicate {
	$Audio::Nama::parser->do_part("$item{user_alias} $item{predicate}"); 1
}
user_alias: ident { 
		$Audio::Nama::user_alias{$item{ident}} }
user_command: ident { return $item{ident} if $Audio::Nama::user_command{$item{ident}} }
key: /\w+/ 			
someval: /[\w.+-]+/ 
sign: '+' | '-' | '*' | '/' 
value: /[+-]?([\d_]+(\.\d*)?|\.\d+)([eE][+-]?\d+)?/
float: /\d+\.\d+/   
op_id: /[A-Z]+/		
parameter: /\d+/	
dd: /\d+/			
shellish: /"(.+)"/ { $1 }
shellish: /'(.+)'/ { $1 }
shellish: anytag | <error>
jack_port: shellish
effect: /\w[\w:]*/   | <error: illegal identifier, only word characters and colon allowed>
project_id: ident slash(?) { $item{ident} }
slash: '/'
anytag: /\S+/
ident: /[-\w]+/  
statefile: /[-:\w\.]+/
marktime: /\d+\.\d+/ 
markname: /[A-Za-z]\w*/ { 
	print("$item[1]: non-existent mark name. Skipping\n"), return undef 
		unless $Audio::Nama::Mark::by_name{$item[1]};
	$item[1];
}
path: shellish
modifier: 'audioloop' | 'select' | 'reverse' | 'playat' | value
end: /[;\s]*$/ 		
help_effect: _help_effect effect { Audio::Nama::Text::help_effect($item{effect}) ; 1}
find_effect: _find_effect anytag(s) { 
	Audio::Nama::Text::find_effect(@{$item{"anytag(s)"}}); 1}
help: _help 'yml' { Audio::Nama::pager($Audio::Nama::commands_yml); 1}
help: _help anytag  { Audio::Nama::Text::help($item{anytag}) ; 1}
help: _help { print $Audio::Nama::help_screen ; 1}
project_name: _project_name { 
	print "project name: ", $Audio::Nama::project_name, $/; 1}
create_project: _create_project project_id { 
	Audio::Nama::Text::t_create_project $item{project_id} ; 1}
list_projects: _list_projects { Audio::Nama::list_projects() ; 1}
load_project: _load_project project_id {
	Audio::Nama::Text::t_load_project $item{project_id} ; 1}
new_project_template: _new_project_template key text(?) {
	Audio::Nama::new_project_template($item{key}, $item{text});
	1;
}
use_project_template: _use_project_template key {
	Audio::Nama::use_project_template($item{key}); 1;
}
list_project_templates: _list_project_templates {
	Audio::Nama::list_project_templates(); 1;
}
remove_project_template: _remove_project_template key(s) {
	Audio::Nama::remove_project_template(@{$item{'key(s)'}}); 1;
}
save_state: _save_state ident { Audio::Nama::save_state( $item{ident}); 1}
save_state: _save_state { Audio::Nama::save_state(); 1}
get_state: _get_state statefile {
 	Audio::Nama::load_project( 
 		name => $Audio::Nama::project_name,
 		settings => $item{statefile}
 		); 1}
get_state: _get_state {
 	Audio::Nama::load_project( name => $Audio::Nama::project_name,) ; 1}
getpos: _getpos {  
	print Audio::Nama::d1( Audio::Nama::eval_iam q(getpos) ), $/; 1}
setpos: _setpos timevalue {
	Audio::Nama::set_position($item{timevalue}); 1}
forward: _forward timevalue {
	Audio::Nama::forward( $item{timevalue} ); 1}
rewind: _rewind timevalue {
	Audio::Nama::rewind( $item{timevalue} ); 1}
timevalue: min_sec | seconds
seconds: value
min_sec: /\d+/ ':' /\d+/ { $item[1] * 60 + $item[3] }
to_start: _to_start { Audio::Nama::to_start(); 1 }
to_end: _to_end { Audio::Nama::to_end(); 1 }
add_track: _add_track track_name(s) {
	Audio::Nama::add_track(@{$item{'track_name(s)'}}); 1}
add_tracks: _add_tracks track_name(s) {
	map{ Audio::Nama::add_track($_)  } @{$item{'track_name(s)'}}; 1}
track_name: ident
move_to_bus: _move_to_bus existing_bus_name {
	$Audio::Nama::this_track->set( group => $item{existing_bus_name}); 1
} 
set_track: _set_track key someval {
	 $Audio::Nama::this_track->set( $item{key}, $item{someval} ); 1}
dump_track: _dump_track { Audio::Nama::pager($Audio::Nama::this_track->dump); 1}
dump_group: _dump_group { Audio::Nama::pager($Audio::Nama::main->dump); 1}
dump_all: _dump_all { Audio::Nama::dump_all(); 1}
remove_track: _remove_track quiet(?) { 
 	my $quiet = scalar @{$item{'quiet(?)'}};
 	$Audio::Nama::this_track->remove, return 1 if $quiet or $Audio::Nama::quietly_remove_tracks;
 	my $name = $Audio::Nama::this_track->name; 
 	my $reply = $Audio::Nama::term->readline("remove track $name? [n] ");
 	if ( $reply =~ /y/i ){
 		print "Removing track. All WAV files will be kept.\n";
 		$Audio::Nama::this_track->remove; 
 	}
 	1;
}
quiet: 'quiet'
link_track: _link_track track_name target project {
	Audio::Nama::add_track_alias_project($item{track_name}, $item{target}, $item{project}); 1
}
link_track: _link_track track_name target {
	Audio::Nama::add_track_alias($item{track_name}, $item{target}); 1
}
target: track_name
project: ident
set_region: _set_region beginning ending { 
	Audio::Nama::set_region( @item{ qw( beginning ending ) } );
	1;
}
set_region: _set_region beginning { Audio::Nama::set_region( $item{beginning}, 'END' );
	1;
}
remove_region: _remove_region { Audio::Nama::remove_region(); 1; }
new_region: _new_region beginning ending track_name(?) {
	my $name = $item{'track_name(?)'}->[0];
	Audio::Nama::new_region(@item{qw(beginning ending)}, $name); 1
}
shift_track: _shift_track start_position {
	my $pos = $item{start_position};
	if ( $pos =~ /\d+\.\d+/ ){
		print $Audio::Nama::this_track->name, ": Shifting start time to $pos seconds\n";
		$Audio::Nama::this_track->set(playat => $pos);
		1;
	}
	elsif ( $Audio::Nama::Mark::by_name{$pos} ){
		my $time = Audio::Nama::Mark::mark_time( $pos );
		print $Audio::Nama::this_track->name, 
			qq(: Shifting start time to mark "$pos", $time seconds\n);
		$Audio::Nama::this_track->set(playat => $pos);
		1;
	} else { print 
	"Shift value is neither decimal nor mark name. Skipping.\n";
	0;
	}
}
start_position:  float | mark_name
mark_name: ident
unshift_track: _unshift_track {
	$Audio::Nama::this_track->set(playat => undef)
}
beginning: marktime | markname
ending: 'END' | marktime | markname 
generate: _generate { Audio::Nama::generate_setup(); 1}
arm: _arm { Audio::Nama::arm(); 1}
connect: _connect { Audio::Nama::connect_transport(); 1}
disconnect: _disconnect { Audio::Nama::disconnect_transport(); 1}
engine_status: _engine_status { 
	print(Audio::Nama::eval_iam q(engine-status)); print "\n" ; 1}
start: _start { Audio::Nama::start_transport(); 1}
stop: _stop { Audio::Nama::stop_transport(); 1}
ecasound_start: _ecasound_start { Audio::Nama::eval_iam("stop"); 1}
ecasound_stop: _ecasound_stop  { Audio::Nama::eval_iam("start"); 1}
show_tracks: _show_tracks { 	
	Audio::Nama::pager( Audio::Nama::Text::show_tracks(Audio::Nama::Text::showlist()));
	1;
}
show_tracks_all: _show_tracks_all { 	
	my $list = [undef, undef, sort{$a->n <=> $b->n} Audio::Nama::Track::all()];
	Audio::Nama::pager(Audio::Nama::Text::show_tracks($list));
	1;
}
show_bus_tracks: _show_bus_tracks { 	
	my $bus = $Audio::Nama::bn{$Audio::Nama::this_bus};
	my $list = $bus->trackslist;
	Audio::Nama::pager(Audio::Nama::Text::show_tracks($list));
	1;
}
modifiers: _modifiers modifier(s) {
 	$Audio::Nama::this_track->set(modifiers => (join q(,),
	@{$item{"modifier(s)"}}, q() ));
	1;}
modifiers: _modifiers { print $Audio::Nama::this_track->modifiers, "\n"; 1}
nomodifiers: _nomodifiers { $Audio::Nama::this_track->set(modifiers => ""); 1}
show_chain_setup: _show_chain_setup { Audio::Nama::pager(Audio::Nama::ChainSetup::ecasound_chain_setup); 1}
show_io: _show_io { Audio::Nama::ChainSetup::show_io(); 1}
show_track: _show_track {
	my $output = $Audio::Nama::format_top;
	$output .= Audio::Nama::Text::show_tracks_section($Audio::Nama::this_track);
	$output .= Audio::Nama::Text::show_region();
	$output .= Audio::Nama::Text::show_effects();
	$output .= Audio::Nama::Text::show_versions();
	$output .= Audio::Nama::Text::show_send();
	$output .= Audio::Nama::Text::show_bus();
	$output .= Audio::Nama::Text::show_modifiers();
	$output .= join "", "Signal width: ", Audio::Nama::width($Audio::Nama::this_track->width), "\n";
	$output .= Audio::Nama::Text::show_effect_chain_stack();
	$output .= Audio::Nama::Text::show_inserts();
	Audio::Nama::pager( $output );
	1;}
show_track: _show_track track_name { 
 	Audio::Nama::pager( Audio::Nama::Text::show_tracks( 
	$Audio::Nama::tn{$item{track_name}} )) if $Audio::Nama::tn{$item{track_name}};
	1;}
show_track: _show_track dd {  
	Audio::Nama::pager( Audio::Nama::Text::show_tracks( $Audio::Nama::ti{$item{dd}} )) if
	$Audio::Nama::ti{$item{dd}};
	1;}
show_mode: _show_mode { print STDOUT Audio::Nama::Text::show_status; 1}
bus_rec: _bus_rec {
	my $bus = $Audio::Nama::bn{$Audio::Nama::this_bus}; 
	$bus->set(rw => 'REC');
	$Audio::Nama::tn{$bus->send_id}->busify
		if $bus->send_type eq 'track' and $Audio::Nama::tn{$bus->send_id};
	print "Setting REC-enable for " , $Audio::Nama::this_bus ,
		" bus. You may record member tracks.\n";
	1; }
bus_mon: _bus_mon {
	my $bus = $Audio::Nama::bn{$Audio::Nama::this_bus}; 
	$bus->set(rw => 'MON');
	$Audio::Nama::tn{$bus->send_id}->busify
		if $bus->send_type eq 'track' and $Audio::Nama::tn{$bus->send_id};
	print "Setting MON mode for " , $Audio::Nama::this_bus , 
		" bus. Monitor only for member tracks.\n";
 	1  
}
bus_off: _bus_off {
	my $bus = $Audio::Nama::bn{$Audio::Nama::this_bus}; 
	$bus->set(rw => 'OFF');
	if($bus->send_type eq 'track' and my $mix = $Audio::Nama::tn{$bus->send_id})
	{ $mix->set(rw => 'OFF') }
	print "Setting OFF mode for " , $Audio::Nama::this_bus,
		" bus. Member tracks disabled.\n"; 1  
}
bus_version: _bus_version { 
	use warnings;
	no warnings qw(uninitialized);
	print $Audio::Nama::this_bus, " bus default version is: ", 
		$Audio::Nama::bn{$Audio::Nama::this_bus}->version, "\n" ; 1}
bus_version: _bus_version dd { 
	my $n = $item{dd};
	$n = undef if $n == 0;
	$Audio::Nama::bn{$Audio::Nama::this_bus}->set( version => $n ); 
	print $Audio::Nama::this_bus, " bus default version set to: ", 
		$Audio::Nama::bn{$Audio::Nama::this_bus}->version, "\n" ; 1}
mixdown: _mixdown { Audio::Nama::Text::mixdown(); 1}
mixplay: _mixplay { Audio::Nama::Text::mixplay(); 1}
mixoff:  _mixoff  { Audio::Nama::Text::mixoff(); 1}
automix: _automix { Audio::Nama::automix(); 1 }
autofix_tracks: _autofix_tracks { Audio::Nama::command_process("for mon; fixdc; normalize"); 1 }
master_on: _master_on { Audio::Nama::master_on(); 1 }
master_off: _master_off { Audio::Nama::master_off(); 1 }
exit: _exit {   Audio::Nama::save_state($Audio::Nama::state_store_file); 
					Audio::Nama::cleanup_exit();
                    1}	
source: _source source_id { $Audio::Nama::this_track->set_source($item{source_id}); 1 }
source_id: shellish
source: _source { 
	print $Audio::Nama::this_track->name, ": input set to ", $Audio::Nama::this_track->input_object, "\n";
	print "however track status is ", $Audio::Nama::this_track->rec_status, "\n"
		if $Audio::Nama::this_track->rec_status ne 'REC';
	1;
}
send: _send jack_port { $Audio::Nama::this_track->set_send($item{jack_port}); 1}
send: _send { $Audio::Nama::this_track->set_send(); 1}
remove_send: _remove_send {
					$Audio::Nama::this_track->set(send_type => undef);
					$Audio::Nama::this_track->set(send_id => undef); 1
}
stereo: _stereo { 
	$Audio::Nama::this_track->set(width => 2); 
	print $Audio::Nama::this_track->name, ": setting to stereo\n";
	1;
}
mono: _mono { 
	$Audio::Nama::this_track->set(width => 1); 
	print $Audio::Nama::this_track->name, ": setting to mono\n";
	1; }
off: 'Xxx' {}
rec: 'Xxx' {}
mon: 'Xxx' {}
command: rw end 
rw_setting: 'rec'|'mon'|'off'
rw: rw_setting {
	Audio::Nama::rw_set($Audio::Nama::Bus::by_name{$Audio::Nama::this_bus},$Audio::Nama::this_track,$item{rw_setting}); 1
}
rec_defeat: _rec_defeat { 
	$Audio::Nama::this_track->set(rec_defeat => 1);
	print $Audio::Nama::this_track->name, ": WAV recording disabled!\n";
}
rec_enable: _rec_enable { 
	$Audio::Nama::this_track->set(rec_defeat => 0);
	print $Audio::Nama::this_track->name, ": WAV recording enabled";
	my $rw = $Audio::Nama::bn{$Audio::Nama::this_track->group}->rw;
	if ( $rw ne 'REC'){
		print qq(, but bus "),$Audio::Nama::this_track->group, qq(" has rw setting of $rw.\n),
		"No WAV file will be recorded.\n";
	} else { print "!\n" }
}
set_version: _set_version dd { $Audio::Nama::this_track->set_version($item{dd}); 1}
vol: _vol value { 
	$Audio::Nama::this_track->vol or 
		print( $Audio::Nama::this_track->name . ": no volume control available\n"), return;
	Audio::Nama::modify_effect(
		$Audio::Nama::this_track->vol,
		0,
		undef,
		$item{value});
	1;
} 
vol: _vol sign(?) value { 
	$Audio::Nama::this_track->vol or 
		print( $Audio::Nama::this_track->name . ": no volume control available\n"), return;
	Audio::Nama::modify_effect(
		$Audio::Nama::this_track->vol,
		0,
		$item{'sign(?)'}->[0],
		$item{value});
	1;
} 
vol: _vol { print $Audio::Nama::copp{$Audio::Nama::this_track->vol}[0], "\n" ; 1}
mute: _mute { $Audio::Nama::this_track->mute; 1}
unmute: _unmute { $Audio::Nama::this_track->unmute; 1}
solo: _solo ident(s) {
	Audio::Nama::solo(@{$item{'ident(s)'}}); 1
}
solo: _solo { Audio::Nama::solo($Audio::Nama::this_track->name); 1}
all: _all { Audio::Nama::all() ; 1}
nosolo: _nosolo { Audio::Nama::nosolo() ; 1}
unity: _unity { 
	Audio::Nama::effect_update_copp_set( 
		$Audio::Nama::this_track->vol, 
		0, 
		$Audio::Nama::unity_level{$Audio::Nama::cops{$Audio::Nama::this_track->vol}->{type}}
	);
	1;}
pan: _pan dd { 
	Audio::Nama::effect_update_copp_set( $Audio::Nama::this_track->pan, 0, $item{dd});
	1;} 
pan: _pan sign dd {
	Audio::Nama::modify_effect( $Audio::Nama::this_track->pan, 0, $item{sign}, $item{dd} );
	1;} 
pan: _pan { print $Audio::Nama::copp{$Audio::Nama::this_track->pan}[0], "\n"; 1}
pan_right: _pan_right { Audio::Nama::pan_check( 100 ); 1}
pan_left:  _pan_left  { Audio::Nama::pan_check(   0 ); 1}
pan_center: _pan_center { Audio::Nama::pan_check(  50 ); 1}
pan_back:  _pan_back {
	my $old = $Audio::Nama::this_track->old_pan_level;
	if (defined $old){
		Audio::Nama::effect_update_copp_set(
			$Audio::Nama::this_track->pan,	
			0, 					
			$old,				
		);
		$Audio::Nama::this_track->set(old_pan_level => undef);
	}
1;}
remove_mark: _remove_mark dd {
	my @marks = Audio::Nama::Mark::all();
	$marks[$item{dd}]->remove if defined $marks[$item{dd}];
	1;}
remove_mark: _remove_mark ident { 
	my $mark = $Audio::Nama::Mark::by_name{$item{ident}};
	$mark->remove if defined $mark;
	1;}
remove_mark: _remove_mark { 
	return unless (ref $Audio::Nama::this_mark) =~ /Mark/;
	$Audio::Nama::this_mark->remove;
	1;}
new_mark: _new_mark ident { Audio::Nama::drop_mark $item{ident}; 1}
new_mark: _new_mark {  Audio::Nama::drop_mark(); 1}
next_mark: _next_mark { Audio::Nama::next_mark(); 1}
previous_mark: _previous_mark { Audio::Nama::previous_mark(); 1}
loop_enable: _loop_enable someval(s) {
	my @new_endpoints = @{ $item{"someval(s)"}}; 
	$Audio::Nama::loop_enable = 1;
	@Audio::Nama::loop_endpoints = (@new_endpoints, @Audio::Nama::loop_endpoints); 
	@Audio::Nama::loop_endpoints = @Audio::Nama::loop_endpoints[0,1];
	1;}
loop_disable: _loop_disable { $Audio::Nama::loop_enable = 0; 1}
name_mark: _name_mark ident {$Audio::Nama::this_mark->set_name( $item{ident}); 1}
list_marks: _list_marks { 
	my $i = 0;
	map{ print( $_->{time} == $Audio::Nama::this_mark->{time} ? q(*) : q()
	,join " ", $i++, sprintf("%.1f", $_->{time}), $_->name, "\n")  } 
		  @Audio::Nama::Mark::all;
	my $start = my $end = "undefined";
	print "now at ", sprintf("%.1f", Audio::Nama::eval_iam "getpos"), "\n";
	1;}
to_mark: _to_mark dd {
	my @marks = Audio::Nama::Mark::all();
	$marks[$item{dd}]->jump_here;
	1;}
to_mark: _to_mark ident { 
	my $mark = $Audio::Nama::Mark::by_name{$item{ident}};
	$mark->jump_here if defined $mark;
	1;}
modify_mark: _modify_mark sign value {
	my $newtime = eval($Audio::Nama::this_mark->{time} . $item{sign} . $item{value});
	$Audio::Nama::this_mark->set( time => $newtime );
	print $Audio::Nama::this_mark->name, ": set to ", Audio::Nama::d2( $newtime), "\n";
	print "adjusted to ",$Audio::Nama::this_mark->time, "\n" 
		if $Audio::Nama::this_mark->time != $newtime;
	Audio::Nama::eval_iam("setpos ".$Audio::Nama::this_mark->time);
	$Audio::Nama::regenerate_setup++;
	1;
	}
modify_mark: _modify_mark value {
	$Audio::Nama::this_mark->set( time => $item{value} );
	my $newtime = $item{value};
	print $Audio::Nama::this_mark->name, ": set to ", Audio::Nama::d2($newtime),"\n";
	print "adjusted to ",$Audio::Nama::this_mark->time, "\n" 
		if $Audio::Nama::this_mark->time != $newtime;
	Audio::Nama::eval_iam("setpos ".$Audio::Nama::this_mark->time);
	$Audio::Nama::regenerate_setup++;
	1;
	}		
remove_effect: _remove_effect op_id(s) {
	Audio::Nama::mute();
	map{ print "removing effect id: $_\n"; Audio::Nama::remove_effect( $_ )
	} grep { $_ }  @{ $item{"op_id(s)"}} ;
	Audio::Nama::sleeper(0.5);
	Audio::Nama::unmute();
	1;}
add_controller: _add_controller parent effect value(s?) {
	my $code = $item{effect};
	my $parent = $item{parent};
	my $values = $item{"value(s?)"};
	my $id = Audio::Nama::Text::t_add_ctrl($parent, $code, $values);
	if($id)
	{
		my $i = 	Audio::Nama::effect_index($code);
		my $iname = $Audio::Nama::effects[$i]->{name};
		my $pi = 	Audio::Nama::effect_index($Audio::Nama::cops{$parent}->{type});
		my $pname = $Audio::Nama::effects[$pi]->{name};
		print "\nAdded $id ($iname) to $parent ($pname)\n\n";
		$Audio::Nama::this_op = $id; 
	}
	1;
}
add_effect: _add_effect effect value(s?) {
	my $code = $item{effect};
	my $values = $item{"value(s?)"};
 	my $id = Audio::Nama::Text::t_add_effect($Audio::Nama::this_track, $code, $values);
	if ($id)
	{
		my $i = Audio::Nama::effect_index($code);
		my $iname = $Audio::Nama::effects[$i]->{name};
		$Audio::Nama::this_op = $id; 
		print "\nAdded $id ($iname)\n\n";
	}
 	1;
}
insert_effect: _insert_effect before effect value(s?) {
	my $before = $item{before};
	my $code = $item{effect};
	my $values = $item{"value(s?)"};
	print join ", ", @{$values} if $values;
	my $id = Audio::Nama::Text::t_insert_effect($before, $code, $values);
	if($id)
	{
		my $i = Audio::Nama::effect_index($code);
		my $iname = $Audio::Nama::effects[$i]->{name};
		my $bi = 	Audio::Nama::effect_index($Audio::Nama::cops{$before}->{type});
		my $bname = $Audio::Nama::effects[$bi]->{name};
 		print "\nInserted $id ($iname) before $before ($bname)\n\n";
	}
	1;}
before: op_id
parent: op_id
modify_effect: _modify_effect parameter(s /,/) value {
	print("Operator \"$Audio::Nama::this_op\" does not exist.\n"), return 1
		unless $Audio::Nama::cops{$Audio::Nama::this_op};
	Audio::Nama::modify_multiple_effects( 
		[$Audio::Nama::this_op], 
		$item{'parameter(s)'},
		undef,
		$item{value});
	print Audio::Nama::Text::show_effect($Audio::Nama::this_op);
	1;
}
modify_effect: _modify_effect parameter(s /,/) sign value {
	print("Operator \"$Audio::Nama::this_op\" does not exist.\n"), return 1
		unless $Audio::Nama::cops{$Audio::Nama::this_op};
	Audio::Nama::modify_multiple_effects( [$Audio::Nama::this_op], @item{qw(parameter(s) sign value)});
	print Audio::Nama::Text::show_effect($Audio::Nama::this_op);
	1;
}
modify_effect: _modify_effect op_id(s /,/) parameter(s /,/) value {
	Audio::Nama::modify_multiple_effects( @item{qw(op_id(s) parameter(s) sign value)});
	Audio::Nama::pager(Audio::Nama::Text::show_effect(@{ $item{'op_id(s)'} }));
	1;
}
modify_effect: _modify_effect op_id(s /,/) parameter(s /,/) sign value {
	Audio::Nama::modify_multiple_effects( @item{qw(op_id(s) parameter(s) sign value)});
	Audio::Nama::pager(Audio::Nama::Text::show_effect(@{ $item{'op_id(s)'} }));
	1;
}
position_effect: _position_effect op_to_move new_following_op {
	my $op = $item{op_to_move};
	my $pos = $item{new_following_op};
	Audio::Nama::position_effect($op, $pos);
	1;
}
op_to_move: op_id
new_following_op: op_id
show_effect: _show_effect op_id(s) {
	my @lines = 
		map{ Audio::Nama::Text::show_effect($_) } 
		grep{ $Audio::Nama::cops{$_} }
		@{ $item{'op_id(s)'}};
	$Audio::Nama::this_op = $item{'op_id(s)'}->[-1];
	Audio::Nama::pager(@lines); 1
}
show_effect: _show_effect {
	print("Operator \"$Audio::Nama::this_op\" does not exist.\n"), return 1
	unless $Audio::Nama::cops{$Audio::Nama::this_op};
	print Audio::Nama::Text::show_effect($Audio::Nama::this_op);
	1;
}
new_bunch: _new_bunch ident(s) { Audio::Nama::Text::bunch( @{$item{'ident(s)'}}); 1}
list_bunches: _list_bunches { Audio::Nama::Text::bunch(); 1}
remove_bunches: _remove_bunches ident(s) { 
 	map{ delete $Audio::Nama::bunch{$_} } @{$item{'ident(s)'}}; 1}
add_to_bunch: _add_to_bunch ident(s) { Audio::Nama::Text::add_to_bunch( @{$item{'ident(s)'}});1 }
list_versions: _list_versions { 
	print join " ", @{$Audio::Nama::this_track->versions}, "\n"; 1}
ladspa_register: _ladspa_register { 
	Audio::Nama::pager( Audio::Nama::eval_iam("ladspa-register")); 1}
preset_register: _preset_register { 
	Audio::Nama::pager( Audio::Nama::eval_iam("preset-register")); 1}
ctrl_register: _ctrl_register { 
	Audio::Nama::pager( Audio::Nama::eval_iam("ctrl-register")); 1}
preview: _preview { Audio::Nama::set_preview_mode(); 1}
doodle: _doodle { Audio::Nama::set_doodle_mode(); 1 }
normalize: _normalize { $Audio::Nama::this_track->normalize; 1}
fixdc: _fixdc { $Audio::Nama::this_track->fixdc; 1}
destroy_current_wav: _destroy_current_wav { Audio::Nama::destroy_current_wav(); 1 }
memoize: _memoize { 
	package Audio::Nama::Wav;
	$Audio::Nama::memoize = 1;
	memoize('candidates'); 1
}
unmemoize: _unmemoize {
	package Audio::Nama::Wav;
	$Audio::Nama::memoize = 0;
	unmemoize('candidates'); 1
}
import_audio: _import_audio path frequency {
	Audio::Nama::import_audio($Audio::Nama::this_track, $item{path}, $item{frequency}); 1;
}
import_audio: _import_audio path {
	Audio::Nama::import_audio($Audio::Nama::this_track, $item{path}); 1;
}
frequency: value
list_history: _list_history {
	my @history = $Audio::Nama::term->GetHistory;
	my %seen;
	map { print "$_\n" unless $seen{$_}; $seen{$_}++ } @history
}
main_off: _main_off { 
	$Audio::Nama::main_out = 0;
1;
} 
main_on: _main_on { 
	$Audio::Nama::main_out = 1;
1;
} 
add_send_bus_cooked: _add_send_bus_cooked bus_name destination {
	Audio::Nama::add_send_bus( $item{bus_name}, $item{destination}, 'cooked' );
	1;
}
add_send_bus_raw: _add_send_bus_raw bus_name destination {
	Audio::Nama::add_send_bus( $item{bus_name}, $item{destination}, 'raw' );
	1;
}
add_sub_bus: _add_sub_bus bus_name { Audio::Nama::add_sub_bus( $item{bus_name}); 1 }
existing_bus_name: bus_name {
	if ( $Audio::Nama::bn{$item{bus_name}} ){  $item{bus_name} }
	else { print("$item{bus_name}: no such bus\n"); undef }
}
bus_name: ident 
user_bus_name: ident 
{
	if($item[1] =~ /^[A-Z]/){ $item[1] }
	else { print("Bus name must begin with capital letter.\n"); undef} 
}
destination: jack_port 
remove_bus: _remove_bus existing_bus_name { 
	$Audio::Nama::bn{$item{existing_bus_name}}->remove; 1; 
}
update_send_bus: _update_send_bus existing_bus_name {
 	Audio::Nama::update_send_bus( $item{existing_bus_name} );
 	1;
}
set_bus: _set_bus key someval { $Audio::Nama::bn{$Audio::Nama::this_bus}->set($item{key} => $item{someval}); 1 }
list_buses: _list_buses { Audio::Nama::pager(map{ $_->dump } Audio::Nama::Bus::all()) ; 1}
add_insert: _add_insert prepost send_id return_id(?) {
	my $return_id = $item{'return_id(?)'}->[0];
	my $send_id = $item{send_id};
	Audio::Nama::Insert::add_insert( "$item{prepost}fader_insert",$send_id, $return_id);
	1;
}
prepost: 'pre' | 'post'
send_id: jack_port
return_id: jack_port
set_insert_wetness: _set_insert_wetness prepost(?) parameter {
	my $prepost = $item{'prepost(?)'}->[0];
	my $p = $item{parameter};
	my $id = Audio::Nama::Insert::get_id($Audio::Nama::this_track,$prepost);
	print($Audio::Nama::this_track->name.  ": Missing or ambiguous insert. Skipping\n"), 
		return 1 unless $id;
	print("wetness parameter must be an integer between 0 and 100\n"), 
		return 1 unless ($p <= 100 and $p >= 0);
	my $i = $Audio::Nama::Insert::by_index{$id};
	print("track '",$Audio::Nama::this_track->n, "' has no insert.  Skipping.\n"),
		return 1 unless $i;
	$i->{wetness} = $p;
	Audio::Nama::modify_effect($i->wet_vol, 0, undef, $p);
	Audio::Nama::sleeper(0.1);
	Audio::Nama::modify_effect($i->dry_vol, 0, undef, 100 - $p);
	1;
}
set_insert_wetness: _set_insert_wetness prepost(?) {
	my $prepost = $item{'prepost(?)'}->[0];
	my $id = Audio::Nama::Insert::get_id($Audio::Nama::this_track,$prepost);
	$id or print($Audio::Nama::this_track->name.  ": Missing or ambiguous insert. Skipping\n"), return 1 ;
	my $i = $Audio::Nama::Insert::by_index{$id};
	 print "The insert is ", 
		$i->wetness, "% wet, ", (100 - $i->wetness), "% dry.\n";
}
remove_insert: _remove_insert prepost(?) { 
	my $prepost = $item{'prepost(?)'}->[0];
	my $id = Audio::Nama::Insert::get_id($Audio::Nama::this_track,$prepost);
	$id or print($Audio::Nama::this_track->name.  ": Missing or ambiguous insert. Skipping\n"), return 1 ;
	print $Audio::Nama::this_track->name.": removing $prepost". "fader insert\n";
	$Audio::Nama::Insert::by_index{$id}->remove;
	1;
}
cache_track: _cache_track additional_time(?) {
	my $time = $item{'additional_time(?)'}->[0];
	Audio::Nama::cache_track($Audio::Nama::this_track, $time); 1 
}
additional_time: float | dd
uncache_track: _uncache_track { Audio::Nama::uncache_track($Audio::Nama::this_track); 1 }
new_effect_chain: _new_effect_chain ident op_id(s?) {
	Audio::Nama::new_effect_chain($Audio::Nama::this_track, $item{ident}, @{ $item{'op_id(s?)'} });
	1;
}
add_effect_chain: _add_effect_chain ident {
	Audio::Nama::add_effect_chain($Audio::Nama::this_track, $item{ident});
	1;
}
delete_effect_chain: _delete_effect_chain ident(s) {
	map{ delete $Audio::Nama::effect_chain{$_} } @{ $item{'ident(s)'} };
	1;
}
list_effect_chains: _list_effect_chains ident(s?) {
	Audio::Nama::pager(Audio::Nama::list_effect_chains( @{ $item{'ident(s?)'} } )); 1;
}
bypass_effects:   _bypass_effects { 
	Audio::Nama::push_effect_chain($Audio::Nama::this_track) and
	print $Audio::Nama::this_track->name, ": bypassing effects\n"; 1}
restore_effects: _restore_effects { 
	Audio::Nama::restore_effects($Audio::Nama::this_track) and
	print $Audio::Nama::this_track->name, ": restoring effects\n"; 1}
overwrite_effect_chain: _overwrite_effect_chain ident {
	Audio::Nama::overwrite_effect_chain($Audio::Nama::this_track, $item{ident}); 1;
}
bunch_name: ident { 
	Audio::Nama::is_bunch($item{ident}) or Audio::Nama::bunch_tracks($item{ident})
		or print("$item{ident}: no such bunch name.\n"), return; 
	$item{ident};
}
effect_profile_name: ident
existing_effect_profile_name: ident {
	print("$item{ident}: no such effect profile\n"), return
		unless $Audio::Nama::effect_profile{$item{ident}};
	$item{ident}
}
new_effect_profile: _new_effect_profile bunch_name effect_profile_name {
	Audio::Nama::new_effect_profile($item{bunch_name}, $item{effect_profile_name}); 1 }
delete_effect_profile: _delete_effect_profile existing_effect_profile_name {
	Audio::Nama::delete_effect_profile($item{existing_effect_profile_name}); 1 }
apply_effect_profile: _apply_effect_profile effect_profile_name {
	Audio::Nama::apply_effect_profile(\&Audio::Nama::overwrite_effect_chain, $item{effect_profile_name}); 1 }
overlay_effect_profile: _overlay_effect_profile effect_profile_name {
	Audio::Nama::apply_effect_profile(\&Audio::Nama::add_effect_chain, $item{effect_profile_name}); 1 }
list_effect_profiles: _list_effect_profiles {
	Audio::Nama::pager(Audio::Nama::list_effect_profiles()); 1 }
do_script: _do_script shellish { Audio::Nama::do_script($item{shellish});1}
scan: _scan { print "scanning ", Audio::Nama::this_wav_dir(), "\n"; Audio::Nama::rememoize() }
add_fade: _add_fade in_or_out mark1 duration(?)
{ 	Audio::Nama::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					duration => $item{'duration(?)'}->[0] 
								|| $Audio::Nama::default_fade_length, 
					relation => 'fade_from_mark',
					track => $Audio::Nama::this_track->name,
	); 
	++$Audio::Nama::regenerate_setup;
}
add_fade: _add_fade in_or_out duration(?) mark1 
{ 	Audio::Nama::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					duration => $item{'duration(?)'}->[0] 
								|| $Audio::Nama::default_fade_length, 
					track => $Audio::Nama::this_track->name,
					relation => 'fade_to_mark',
	);
	++$Audio::Nama::regenerate_setup;
}
add_fade: _add_fade in_or_out mark1 mark2
{ 	Audio::Nama::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					mark2 => $item{mark2},
					track => $Audio::Nama::this_track->name,
	);
	++$Audio::Nama::regenerate_setup;
}
in_or_out: 'in' | 'out'
duration: value
mark1: markname
mark2: markname
remove_fade: _remove_fade fade_index(s) { 
	my @i = @{ $item{'fade_index(s)'} };
	Audio::Nama::Text::remove_fade($_) for (@i);
	$Audio::Nama::regenerate_setup++;
	1
}
fade_index: dd 
 { if ( $Audio::Nama::Fade::by_index{$item{dd}} ){ return $item{dd}}
   else { print("invalid fade number: $item{dd}\n"); return 0 }
 }
list_fade: _list_fade {  Audio::Nama::pager(join "\n",
		map{ s/^---//; s/...\s$//; $_} map{$_->dump}
		sort{$a->n <=> $b->n} values %Audio::Nama::Fade::by_index) }
add_comment: _add_comment text { 
 	print $Audio::Nama::this_track->name, ": comment: $item{text}\n"; 
 	$Audio::Nama::this_track->set(comment => $item{text});
 	1;
}
remove_comment: _remove_comment {
 	print $Audio::Nama::this_track->name, ": comment removed\n";
 	$Audio::Nama::this_track->set(comment => undef);
 	1;
}
show_comment: _show_comment {
	map{ print "(",$_->group,") ", $_->name, ": ", $_->comment, "\n"; } $Audio::Nama::this_track;
	1;
}
show_comments: _show_comments {
	map{ print "(",$_->group,") ", $_->name, ": ", $_->comment, "\n"; } Audio::Nama::Track::all();
	1;
}
add_version_comment: _add_version_comment dd(?) text {
	my $t = $Audio::Nama::this_track;
	my $v = $item{'dd(?)'}->[0] // $t->monitor_version // return 1;
	print Audio::Nama::add_version_comment($t,$v,$item{text});
}	
remove_version_comment: _remove_version_comment dd {
	my $t = $Audio::Nama::this_track;
	print Audio::Nama::remove_version_comment($t,$item{dd}); 1
}
show_version_comment: _show_version_comment dd(s?) {
	my $t = $Audio::Nama::this_track;
	my @v = @{$item{'dd(s?)'}};
	if(!@v){ @v = $t->monitor_version}
	@v or return 1;
	Audio::Nama::show_version_comments($t,@v);
	 1;
}
show_version_comments_all: _show_version_comments_all {
	my $t = $Audio::Nama::this_track;
	my @v = @{$t->versions};
	Audio::Nama::show_version_comments($t,@v); 1;
}
set_system_version_comment: _set_system_version_comment dd text {
	print Audio::Nama::set_system_version_comment($Audio::Nama::this_track,@item{qw(dd text)});1;
}
midish_command: _midish_command text {
	Audio::Nama::midish_command( $item{text} ); 1
}
new_edit: _new_edit {
	Audio::Nama::new_edit();
	1;
}
set_edit_points: _set_edit_points { Audio::Nama::set_edit_points(); 1 }
list_edits: _list_edits { Audio::Nama::list_edits(); 1}
destroy_edit: _destroy_edit { Audio::Nama::destroy_edit(); 1}
select_edit: _select_edit dd { Audio::Nama::select_edit($item{dd}); 1}
preview_edit_in: _preview_edit_in { Audio::Nama::edit_action($item[0]); 1}
preview_edit_out: _preview_edit_out { Audio::Nama::edit_action($item[0]); 1}
play_edit: _play_edit { Audio::Nama::edit_action($item[0]); 1}
record_edit: _record_edit { Audio::Nama::edit_action($item[0]); 1}
edit_track: _edit_track { 
	Audio::Nama::select_edit_track('edit_track'); 1}
host_track_alias: _host_track_alias {
	Audio::Nama::select_edit_track('host_alias_track'); 1}
host_track: _host_track { 
	Audio::Nama::select_edit_track('host'); 1}
version_mix_track: _version_mix_track {
	Audio::Nama::select_edit_track('version_mix'); 1}
play_start_mark: _play_start_mark {
	my $mark = $Audio::Nama::this_edit->play_start_mark;
	$mark->jump_here; 1;
}
rec_start_mark: _rec_start_mark {
	$Audio::Nama::this_edit->rec_start_mark->jump_here; 1;
}
rec_end_mark: _rec_end_mark {
	$Audio::Nama::this_edit->rec_end_mark->jump_here; 1;
}
set_play_start_mark: _set_play_start_mark {
	$Audio::Nama::edit_points[0] = Audio::Nama::eval_iam('getpos'); 1}
set_rec_start_mark: _set_rec_start_mark {
	$Audio::Nama::edit_points[1] = Audio::Nama::eval_iam('getpos'); 1}
set_rec_end_mark: _set_rec_end_mark {
	$Audio::Nama::edit_points[2] = Audio::Nama::eval_iam('getpos'); 1}
end_edit_mode: _end_edit_mode { Audio::Nama::end_edit_mode(); 1;}
disable_edits: _disable_edits { Audio::Nama::disable_edits();1 }
merge_edits: _merge_edits { Audio::Nama::merge_edits(); 1; }
explode_track: _explode_track {
	Audio::Nama::explode_track($Audio::Nama::this_track)
}
promote_version_to_track: _promote_version_to_track version {
	my $v = $item{version};
	my $t = $Audio::Nama::this_track;
	$t->versions->[$v] or print($t->name,": version $v does not exist.\n"),
		return;
	Audio::Nama::VersionTrack->new(
		name 	=> $t->name.":$v",
		version => $v, 
		target  => $t->name,
		rw		=> 'MON',
		group   => $t->group,
	);
}
version: dd
read_user_customizations: _read_user_customizations {
	Audio::Nama::setup_user_customization(); 1
}
limit_run_time: _limit_run_time sign(?) dd { 
	my $sign = $item{'sign(?)'}->[-0];
	$Audio::Nama::run_time = $sign
		? eval "$Audio::Nama::length $sign $item{dd}"
		: $item{dd};
	print "Run time limit: ", Audio::Nama::heuristic_time($Audio::Nama::run_time), "\n"; 1;
}
limit_run_time_off: _limit_run_time_off { 
	print "Run timer disabled\n";
	Audio::Nama::disable_length_timer();
	1;
}
offset_run: _offset_run markname {
	Audio::Nama::offset_run( $item{markname} ); 1
}
offset_run_off: _offset_run_off {
	print "no run offset.\n";
	Audio::Nama::offset_run_mode(0); 1
}

command: help
command: help_effect
command: find_effect
command: exit
command: memoize
command: unmemoize
command: stop
command: start
command: getpos
command: setpos
command: forward
command: rewind
command: to_start
command: to_end
command: ecasound_start
command: ecasound_stop
command: preview
command: doodle
command: mixdown
command: mixplay
command: mixoff
command: automix
command: master_on
command: master_off
command: main_off
command: main_on
command: add_track
command: add_tracks
command: link_track
command: import_audio
command: set_track
command: rec
command: mon
command: off
command: rec_defeat
command: rec_enable
command: source
command: send
command: remove_send
command: stereo
command: mono
command: set_version
command: destroy_current_wav
command: list_versions
command: vol
command: mute
command: unmute
command: unity
command: solo
command: nosolo
command: all
command: pan
command: pan_right
command: pan_left
command: pan_center
command: pan_back
command: show_tracks
command: show_tracks_all
command: show_bus_tracks
command: show_track
command: show_mode
command: set_region
command: new_region
command: remove_region
command: shift_track
command: unshift_track
command: modifiers
command: nomodifiers
command: normalize
command: fixdc
command: autofix_tracks
command: remove_track
command: bus_rec
command: bus_mon
command: bus_off
command: bus_version
command: new_bunch
command: list_bunches
command: remove_bunches
command: add_to_bunch
command: save_state
command: get_state
command: list_projects
command: create_project
command: load_project
command: project_name
command: new_project_template
command: use_project_template
command: list_project_templates
command: remove_project_template
command: generate
command: arm
command: connect
command: disconnect
command: show_chain_setup
command: loop_enable
command: loop_disable
command: add_controller
command: add_effect
command: insert_effect
command: modify_effect
command: remove_effect
command: position_effect
command: show_effect
command: add_insert
command: set_insert_wetness
command: remove_insert
command: ctrl_register
command: preset_register
command: ladspa_register
command: list_marks
command: to_mark
command: new_mark
command: remove_mark
command: next_mark
command: previous_mark
command: name_mark
command: modify_mark
command: engine_status
command: dump_track
command: dump_group
command: dump_all
command: show_io
command: list_history
command: add_send_bus_cooked
command: add_send_bus_raw
command: add_sub_bus
command: update_send_bus
command: remove_bus
command: list_buses
command: set_bus
command: new_effect_chain
command: add_effect_chain
command: overwrite_effect_chain
command: delete_effect_chain
command: list_effect_chains
command: bypass_effects
command: restore_effects
command: new_effect_profile
command: apply_effect_profile
command: overlay_effect_profile
command: delete_effect_profile
command: list_effect_profiles
command: cache_track
command: uncache_track
command: do_script
command: scan
command: add_fade
command: remove_fade
command: list_fade
command: add_comment
command: remove_comment
command: show_comment
command: show_comments
command: add_version_comment
command: remove_version_comment
command: show_version_comment
command: show_version_comments_all
command: set_system_version_comment
command: midish_command
command: new_edit
command: set_edit_points
command: list_edits
command: select_edit
command: end_edit_mode
command: destroy_edit
command: preview_edit_in
command: preview_edit_out
command: play_edit
command: record_edit
command: edit_track
command: host_track_alias
command: host_track
command: version_mix_track
command: play_start_mark
command: rec_start_mark
command: rec_end_mark
command: set_play_start_mark
command: set_rec_start_mark
command: set_rec_end_mark
command: disable_edits
command: merge_edits
command: explode_track
command: move_to_bus
command: promote_version_to_track
command: read_user_customizations
command: limit_run_time
command: limit_run_time_off
command: offset_run
command: offset_run_off
_help: /help\b/ | /h\b/
_help_effect: /help_effect\b/ | /hfx\b/ | /he\b/
_find_effect: /find_effect\b/ | /ffx\b/ | /fe\b/
_exit: /exit\b/ | /quit\b/ | /q\b/
_memoize: /memoize\b/
_unmemoize: /unmemoize\b/
_stop: /stop\b/ | /s\b/
_start: /start\b/ | /t\b/
_getpos: /getpos\b/ | /gp\b/
_setpos: /setpos\b/ | /sp\b/
_forward: /forward\b/ | /fw\b/
_rewind: /rewind\b/ | /rw\b/
_to_start: /to_start\b/ | /beg\b/
_to_end: /to_end\b/ | /end\b/
_ecasound_start: /ecasound_start\b/ | /T\b/
_ecasound_stop: /ecasound_stop\b/ | /S\b/
_preview: /preview\b/
_doodle: /doodle\b/
_mixdown: /mixdown\b/ | /mxd\b/
_mixplay: /mixplay\b/ | /mxp\b/
_mixoff: /mixoff\b/ | /mxo\b/
_automix: /automix\b/
_master_on: /master_on\b/ | /mr\b/
_master_off: /master_off\b/ | /mro\b/
_main_off: /main_off\b/
_main_on: /main_on\b/
_add_track: /add_track\b/ | /add\b/ | /new\b/
_add_tracks: /add_tracks\b/ | /add\b/ | /new\b/
_link_track: /link_track\b/ | /link\b/
_import_audio: /import_audio\b/ | /import\b/
_set_track: /set_track\b/
_rec: /rec\b/
_mon: /mon\b/ | /on\b/
_off: /off\b/ | /z\b/
_rec_defeat: /rec_defeat\b/ | /rd\b/
_rec_enable: /rec_enable\b/ | /re\b/
_source: /source\b/ | /src\b/ | /r\b/
_send: /send\b/ | /out\b/ | /aux\b/
_remove_send: /remove_send\b/ | /nosend\b/ | /rms\b/
_stereo: /stereo\b/
_mono: /mono\b/
_set_version: /set_version\b/ | /version\b/ | /n\b/ | /ver\b/
_destroy_current_wav: /destroy_current_wav\b/
_list_versions: /list_versions\b/ | /lver\b/ | /lv\b/
_vol: /vol\b/ | /v\b/
_mute: /mute\b/ | /c\b/ | /cut\b/
_unmute: /unmute\b/ | /C\b/ | /uncut\b/
_unity: /unity\b/
_solo: /solo\b/ | /sl\b/
_nosolo: /nosolo\b/ | /nsl\b/
_all: /all\b/
_pan: /pan\b/ | /p\b/
_pan_right: /pan_right\b/ | /pr\b/
_pan_left: /pan_left\b/ | /pl\b/
_pan_center: /pan_center\b/ | /pc\b/
_pan_back: /pan_back\b/ | /pb\b/
_show_tracks: /show_tracks\b/ | /show\b/ | /lt\b/
_show_tracks_all: /show_tracks_all\b/ | /sha\b/ | /showa\b/
_show_bus_tracks: /show_bus_tracks\b/ | /shb\b/
_show_track: /show_track\b/ | /sh\b/
_show_mode: /show_mode\b/ | /shm\b/
_set_region: /set_region\b/ | /srg\b/
_new_region: /new_region\b/ | /nrg\b/
_remove_region: /remove_region\b/ | /rrg\b/
_shift_track: /shift_track\b/ | /shift\b/ | /playat\b/ | /pat\b/
_unshift_track: /unshift_track\b/ | /unshift\b/
_modifiers: /modifiers\b/ | /mods\b/ | /mod\b/
_nomodifiers: /nomodifiers\b/ | /nomods\b/ | /nomod\b/
_normalize: /normalize\b/ | /norm\b/ | /ecanormalize\b/
_fixdc: /fixdc\b/ | /ecafixdc\b/
_autofix_tracks: /autofix_tracks\b/ | /autofix\b/
_remove_track: /remove_track\b/
_bus_rec: /bus_rec\b/ | /brec\b/ | /grec\b/
_bus_mon: /bus_mon\b/ | /bmon\b/ | /gmon\b/
_bus_off: /bus_off\b/ | /boff\b/ | /goff\b/
_bus_version: /bus_version\b/ | /bn\b/ | /bver\b/ | /bv\b/ | /gver\b/ | /gn\b/ | /gv\b/
_new_bunch: /new_bunch\b/ | /nb\b/
_list_bunches: /list_bunches\b/ | /lb\b/
_remove_bunches: /remove_bunches\b/ | /rb\b/
_add_to_bunch: /add_to_bunch\b/ | /ab\b/
_save_state: /save_state\b/ | /keep\b/ | /save\b/
_get_state: /get_state\b/ | /recall\b/ | /retrieve\b/
_list_projects: /list_projects\b/ | /lp\b/
_create_project: /create_project\b/ | /create\b/
_load_project: /load_project\b/ | /load\b/
_project_name: /project_name\b/ | /project\b/ | /name\b/
_new_project_template: /new_project_template\b/ | /npt\b/
_use_project_template: /use_project_template\b/ | /upt\b/ | /apt\b/
_list_project_templates: /list_project_templates\b/ | /lpt\b/
_remove_project_template: /remove_project_template\b/ | /rpt\b/ | /dpt\b/
_generate: /generate\b/ | /gen\b/
_arm: /arm\b/
_connect: /connect\b/ | /con\b/
_disconnect: /disconnect\b/ | /dcon\b/
_show_chain_setup: /show_chain_setup\b/ | /chains\b/
_loop_enable: /loop_enable\b/ | /loop\b/
_loop_disable: /loop_disable\b/ | /noloop\b/ | /nl\b/
_add_controller: /add_controller\b/ | /acl\b/
_add_effect: /add_effect\b/ | /afx\b/
_insert_effect: /insert_effect\b/ | /ifx\b/
_modify_effect: /modify_effect\b/ | /mfx\b/ | /modify_controller\b/ | /mcl\b/
_remove_effect: /remove_effect\b/ | /rfx\b/ | /remove_controller\b/ | /rcl\b/
_position_effect: /position_effect\b/ | /pfx\b/
_show_effect: /show_effect\b/ | /sfx\b/
_add_insert: /add_insert\b/ | /ain\b/
_set_insert_wetness: /set_insert_wetness\b/ | /wet\b/
_remove_insert: /remove_insert\b/ | /rin\b/
_ctrl_register: /ctrl_register\b/ | /crg\b/
_preset_register: /preset_register\b/ | /prg\b/
_ladspa_register: /ladspa_register\b/ | /lrg\b/
_list_marks: /list_marks\b/ | /lmk\b/ | /lm\b/
_to_mark: /to_mark\b/ | /tmk\b/ | /tom\b/
_new_mark: /new_mark\b/ | /mark\b/ | /k\b/
_remove_mark: /remove_mark\b/ | /rmk\b/ | /rom\b/
_next_mark: /next_mark\b/ | /nmk\b/ | /nm\b/
_previous_mark: /previous_mark\b/ | /pmk\b/ | /pm\b/
_name_mark: /name_mark\b/ | /nmk\b/ | /nom\b/
_modify_mark: /modify_mark\b/ | /move_mark\b/ | /mmk\b/ | /mm\b/
_engine_status: /engine_status\b/ | /egs\b/
_dump_track: /dump_track\b/ | /dumpt\b/ | /dump\b/
_dump_group: /dump_group\b/ | /dumpgroup\b/ | /dumpg\b/
_dump_all: /dump_all\b/ | /dumpall\b/ | /dumpa\b/
_show_io: /show_io\b/ | /showio\b/
_list_history: /list_history\b/ | /lh\b/
_add_send_bus_cooked: /add_send_bus_cooked\b/ | /asbc\b/
_add_send_bus_raw: /add_send_bus_raw\b/ | /asbr\b/
_add_sub_bus: /add_sub_bus\b/ | /asub\b/
_update_send_bus: /update_send_bus\b/ | /usb\b/
_remove_bus: /remove_bus\b/
_list_buses: /list_buses\b/ | /lbs\b/
_set_bus: /set_bus\b/ | /sbs\b/
_new_effect_chain: /new_effect_chain\b/ | /nec\b/
_add_effect_chain: /add_effect_chain\b/ | /aec\b/
_overwrite_effect_chain: /overwrite_effect_chain\b/ | /oec\b/
_delete_effect_chain: /delete_effect_chain\b/ | /dec\b/
_list_effect_chains: /list_effect_chains\b/ | /lec\b/
_bypass_effects: /bypass_effects\b/ | /bypass\b/ | /bye\b/
_restore_effects: /restore_effects\b/ | /restore\b/ | /ref\b/
_new_effect_profile: /new_effect_profile\b/ | /nep\b/
_apply_effect_profile: /apply_effect_profile\b/ | /aep\b/
_overlay_effect_profile: /overlay_effect_profile\b/ | /oep\b/
_delete_effect_profile: /delete_effect_profile\b/ | /dep\b/
_list_effect_profiles: /list_effect_profiles\b/ | /lep\b/
_cache_track: /cache_track\b/ | /cache\b/ | /ct\b/
_uncache_track: /uncache_track\b/ | /uncache\b/ | /unc\b/
_do_script: /do_script\b/ | /do\b/
_scan: /scan\b/
_add_fade: /add_fade\b/ | /afd\b/ | /fade\b/
_remove_fade: /remove_fade\b/ | /rfd\b/
_list_fade: /list_fade\b/ | /lfd\b/
_add_comment: /add_comment\b/ | /comment\b/ | /ac\b/
_remove_comment: /remove_comment\b/ | /rc\b/
_show_comment: /show_comment\b/ | /sc\b/
_show_comments: /show_comments\b/ | /scs\b/
_add_version_comment: /add_version_comment\b/ | /comment\b/ | /avc\b/
_remove_version_comment: /remove_version_comment\b/ | /rvc\b/
_show_version_comment: /show_version_comment\b/ | /svc\b/
_show_version_comments_all: /show_version_comments_all\b/ | /svca\b/
_set_system_version_comment: /set_system_version_comment\b/ | /comment\b/ | /ssvc\b/
_midish_command: /midish_command\b/ | /m\b/
_new_edit: /new_edit\b/ | /ned\b/
_set_edit_points: /set_edit_points\b/ | /sep\b/
_list_edits: /list_edits\b/ | /led\b/
_select_edit: /select_edit\b/ | /sed\b/
_end_edit_mode: /end_edit_mode\b/ | /eem\b/
_destroy_edit: /destroy_edit\b/
_preview_edit_in: /preview_edit_in\b/ | /pei\b/
_preview_edit_out: /preview_edit_out\b/ | /peo\b/
_play_edit: /play_edit\b/ | /ped\b/
_record_edit: /record_edit\b/ | /red\b/
_edit_track: /edit_track\b/ | /et\b/
_host_track_alias: /host_track_alias\b/ | /hta\b/
_host_track: /host_track\b/ | /ht\b/
_version_mix_track: /version_mix_track\b/ | /vmt\b/
_play_start_mark: /play_start_mark\b/ | /psm\b/
_rec_start_mark: /rec_start_mark\b/ | /rsm\b/
_rec_end_mark: /rec_end_mark\b/ | /rem\b/
_set_play_start_mark: /set_play_start_mark\b/ | /spsm\b/
_set_rec_start_mark: /set_rec_start_mark\b/ | /srsm\b/
_set_rec_end_mark: /set_rec_end_mark\b/ | /srem\b/
_disable_edits: /disable_edits\b/ | /ded\b/
_merge_edits: /merge_edits\b/ | /med\b/
_explode_track: /explode_track\b/
_move_to_bus: /move_to_bus\b/ | /mtb\b/
_promote_version_to_track: /promote_version_to_track\b/ | /pvt\b/
_read_user_customizations: /read_user_customizations\b/ | /ruc\b/
_limit_run_time: /limit_run_time\b/ | /lrt\b/
_limit_run_time_off: /limit_run_time_off\b/ | /lro\b/
_offset_run: /offset_run\b/ | /ofr\b/
_offset_run_off: /offset_run_off\b/ | /ofo\b/
__[chain_op_hints_yml]__
---
-
  code: ea
  count: 1
  display: scale
  name: Volume
  params:
    -
      begin: 0
      default: 100
      end: 600
      name: "Level %"
      resolution: 0
-
  code: eadb
  count: 1
  display: scale
  name: Volume
  params:
    -
      begin: -40 
      default: 0
      end: 60
      name: "Level db"
      resolution: 0.5
-
  code: epp
  count: 1
  display: scale
  name: Pan
  params:
    -
      begin: 0
      default: 50
      end: 100
      name: "Level %"
      resolution: 0
-
  code: eal
  count: 1
  display: scale
  name: Limiter
  params:
    -
      begin: 0
      default: 100
      end: 100
      name: "Limit %"
      resolution: 0
-
  code: ec
  count: 2
  display: scale
  name: Compressor
  params:
    -
      begin: 0
      default: 1
      end: 1
      name: "Compression Rate (Db)"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Threshold %"
      resolution: 0
-
  code: eca
  count: 4
  display: scale
  name: "Advanced Compressor"
  params:
    -
      begin: 0
      default: 69
      end: 100
      name: "Peak Level %"
      resolution: 0
    -
      begin: 0
      default: 2
      end: 5
      name: "Release Time (Seconds)"
      resolution: 0
    -
      begin: 0
      default: 0.5
      end: 1
      name: "Fast Compressor Rate"
      resolution: 0
    -
      begin: 0
      default: 1
      end: 1
      name: "Compressor Rate (Db)"
      resolution: 0
-
  code: enm
  count: 5
  display: scale
  name: "Noise Gate"
  params:
    -
      begin: 0
      default: 100
      end: 100
      name: "Threshold Level %"
      resolution: 0
    -
      begin: 0
      default: 200
      end: 2000
      name: "Pre Hold Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 200
      end: 2000
      name: "Attack Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 200
      end: 2000
      name: "Post Hold Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 200
      end: 2000
      name: "Release Time (ms)"
      resolution: 0
-
  code: ef1
  count: 2
  display: scale
  name: "Resonant Bandpass Filter"
  params:
    -
      begin: 0
      default: 0
      end: 20000
      name: "Center Frequency (Hz)"
      resolution: 0
    -
      begin: 0
      default: 0
      end: 2000
      name: "Width (Hz)"
      resolution: 0
-
  code: ef3
  count: 3
  display: scale
  name: "Resonant Lowpass Filter"
  params:
    -
      begin: 0
      default: 0
      end: 5000
      name: "Cutoff Frequency (Hz)"
      resolution: 0
    -
      begin: 0
      default: 0
      end: 2
      name: Resonance
      resolution: 0
    -
      begin: 0
      default: 0
      end: 1
      name: Gain
      resolution: 0
-
  code: efa
  count: 2
  display: scale
  name: "Allpass Filter"
  params:
    -
      begin: 0
      default: 0
      end: 10000
      name: "Delay Samples"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Feedback %"
      resolution: 0
-
  code: efb
  count: 2
  display: scale
  name: "Bandpass Filter"
  params:
    -
      begin: 0
      default: 11000
      end: 11000
      name: "Center Frequency (Hz)"
      resolution: 0
    -
      begin: 0
      default: 22000
      end: 22000
      name: "Width (Hz)"
      resolution: 0
-
  code: efh
  count: 1
  display: scale
  name: "Highpass Filter"
  params:
    -
      begin: 10000
      default: 10000
      end: 22000
      name: "Cutoff Frequency (Hz)"
      resolution: 0
-
  code: efl
  count: 1
  display: scale
  name: "Lowpass Filter"
  params:
    -
      begin: 0
      default: 0
      end: 10000
      name: "Cutoff Frequency (Hz)"
      resolution: 0
-
  code: efr
  count: 2
  display: scale
  name: "Bandreject Filter"
  params:
    -
      begin: 0
      default: 11000
      end: 11000
      name: "Center Frequency (Hz)"
      resolution: 0
    -
      begin: 0
      default: 22000
      end: 22000
      name: "Width (Hz)"
      resolution: 0
-
  code: efs
  count: 2
  display: scale
  name: "Resonator Filter"
  params:
    -
      begin: 0
      default: 11000
      end: 11000
      name: "Center Frequency (Hz)"
      resolution: 0
    -
      begin: 0
      default: 22000
      end: 22000
      name: "Width (Hz)"
      resolution: 0
-
  code: etd
  count: 5
  display: scale
  name: Delay
  params:
    -
      begin: 0
      default: 200
      end: 2000
      name: "Delay Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 0
      end: 2
      name: "Surround Mode (Normal, Surround St., Spread)"
      resolution: 1
    -
      begin: 0
      default: 50
      end: 100
      name: "Number of Delays"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Mix %"
      resolution: 0
    -
      begin: 0
      default: 0
      end: 100
      name: "Feedback %"
      resolution: 0
-
  code: etc
  count: 4
  display: scale
  name: Chorus
  params:
    -
      begin: 0
      default: 200
      end: 2000
      name: "Delay Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 500
      end: 10000
      name: "Variance Time Samples"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Feedback %"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "LFO Frequency (Hz)"
      resolution: 0
-
  code: etr
  count: 3
  display: scale
  name: Reverb
  params:
    -
      begin: 0
      default: 200
      end: 2000
      name: "Delay Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 0
      end: 1
      name: "Surround Mode (0=Normal, 1=Surround)"
      resolution: 1
    -
      begin: 0
      default: 50
      end: 100
      name: "Feedback %"
      resolution: 0
-
  code: ete
  count: 3
  display: scale
  name: "Advanced Reverb"
  params:
    -
      begin: 0
      default: 10
      end: 100
      name: "Room Size (Meters)"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Feedback %"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Wet %"
      resolution: 0
-
  code: etf
  count: 1
  display: scale
  name: "Fake Stereo"
  params:
    -
      begin: 0
      default: 40
      end: 500
      name: "Delay Time (ms)"
      resolution: 0
-
  code: etl
  count: 4
  display: scale
  name: Flanger
  params:
    -
      begin: 0
      default: 200
      end: 1000
      name: "Delay Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 200
      end: 10000
      name: "Variance Time Samples"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Feedback %"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "LFO Frequency (Hz)"
      resolution: 0
-
  code: etm
  count: 3
  display: scale
  name: "Multitap Delay"
  params:
    -
      begin: 0
      default: 200
      end: 2000
      name: "Delay Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 20
      end: 100
      name: "Number of Delays"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Mix %"
      resolution: 0
-
  code: etp
  count: 4
  display: scale
  name: Phaser
  params:
    -
      begin: 0
      default: 200
      end: 2000
      name: "Delay Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 100
      end: 10000
      name: "Variance Time Samples"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Feedback %"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "LFO Frequency (Hz)"
      resolution: 0
-
  code: pn:metronome
  count: 1
  display: scale
  name: Metronome
  params:
    -
      begin: 30
      default: 120
      end: 300
      name: BPM
      resolution: 1
...
;
__[default_namarc]__
#
#
#         Nama Configuration file

#         Notes

#         - This configuration file is distinct from
#           Ecasound's configuration file .ecasoundrc . 
#           In most instances the latter is not required.

#        - The format of this file is YAML, preprocessed to allow
#           comments.
#
#        - A value _must_ be supplied for each 'leaf' field.
#          For example "mixer_out_format: cd-stereo"
#
#        - A value must _not_ be supplied for nodes, i.e.
#          'device:'. The value for 'device' is the entire indented
#          data structure that follows in subsequent lines.
#
#        - Indents are significant. Two spaces indent is
#          required for each sublevel.
#
#        - Use the tilde symbol '~' to represent a null value
#          For example "execute_on_project_load: ~"

# project root directory

# all project directories (or their symlinks) will live here

project_root: ~                  # replaced during first run

# autosave - store current project state as # autosave-2010.8.22-15:08:22.yml

autosave_interval: 0 # time in minutes, 0 (zero) to disable

# define abbreviations

abbreviations:  
  24-mono: s24_le,1,frequency
  24-stereo: s24_le,2,frequency,i
  cd-mono: s16_le,1,44100
  cd-stereo: s16_le,2,44100,i
  frequency: 44100

# define audio devices

devices: 
  jack:
    signal_format: f32_le,N,frequency # do not change this
  consumer:
    ecasound_id: alsa,default
    input_format: cd-stereo
    output_format: cd-stereo
  multi:
    ecasound_id: alsa,ice1712
    input_format: s32_le,12,frequency
    output_format: s32_le,10,frequency
  null:
    ecasound_id: null
    output_format: ~

# ALSA soundcard device assignments and formats

alsa_capture_device: consumer       # for ALSA/OSS
alsa_playback_device: consumer      # for ALSA/OSS
mixer_out_format: cd-stereo         # for ALSA/OSS

# soundcard_channels: 10            # input/output channel selection range (GUI)

# audio file formats

mix_to_disk_format: s16_le,N,frequency,i
raw_to_disk_format: s16_le,N,frequency,i
cache_to_disk_format: f24_le,N,frequency,i

ladspa_sample_rate: frequency

# globals for our chain setups

ecasound_globals_realtime: "-B auto -r -z:mixmode,sum -z:psr "

ecasound_globals_default: "-B auto -z:mixmode,sum -z:psr "

# ecasound_tcp_port: 2868  

# WAVs recorded at the same time get the same numeric suffix

use_group_numbering: 1

# Enable pressing SPACE to start/stop transport (in terminal, cursor in column 1)

press_space_to_start_transport: 1

# commands to execute each time a project is loaded

execute_on_project_load: ~

volume_control_operator: eadb # must be 'ea' or 'eadb'

# effects for use in mastering mode

eq: Parametric1 1 0 0 40 0.125 0 0 200 0.125 0 0 600 0.125 0 0 3300 0.125 0

low_pass: lowpass_iir 106 2

mid_pass: bandpass_iir 520 800 2

high_pass: highpass_iir 1030 2

compressor: sc4 0 3 16 0 1 3.25 0

spatialiser: matrixSpatialiser 0

limiter: tap_limiter 0 0

# Julien Claassen's Notes on Mastering effect defaults
# 
# Eq: All sections are initially off. You can turn them 
# on as needed, one at a time. 
# 
# Bandpass: Default settings are courtesy of Fons
# Adriaensen, who says they will be within 1.5dB of
# flat settings. 
# 
# Compressor is turned off, with reasonable default values 
# set. 
# 
# Spatialiser and limiter: both initially off so you can start out
# clean and slowly work your way from there.
 
# MIDI support
#
# midish_enable: 0  
# 
# midi_input_dev: 
# 
# midi_output_dev:
 
# jack.plumbing - a daemon for auto-connecting JACK clients
# (The default is to use 'jack_connect' which is more reliable)
#
# use_jack_plumbing: 0
#
# increase the following to 0.5 or more if you suffer 2 - 3
# second delays when seeking playback position under JACK
#
# jack_seek_delay: 0.1 # user override for default 
#
# quietly_remove_tracks: 0 # generally ask user to confirm

# initial_user_mode: 0 # preview, doodle, 0

# Nama directory structure and files

# ~/.namarc						# config file
# ~/nama/untitled				# project directory
# ~/nama/untitled/.wav			# wav directory
# ~/nama/untitled/State.yml		# project state
# ~/nama/untitled/Setup.ecs		# Ecasound chain setup
# ~/nama/.effects_cache			# static effects data
# ~/nama/effect_chains			# Nama effect presets
# ~/nama/effect_profiles		# Nama effect profiles
# end


__[custom_pl]__
### custom.pl - Nama user customization file

# See notes at end

##  Prompt section - replaces default user prompt

prompt =>  
	q{
	"nama [". ($this_bus eq 'Main' ? '': "$this_bus/").  
		($this_track ? $this_track->name : '') . "] "
	},


##  Aliases section - shortcuts to any Nama or user-defined commands

aliases => 
	{
		mbs => 'move_to_bus',
		pcv => 'promote_current_version',
		hi => 'greet',
	},


## Commands section - user defined commands

commands => 
	{
		promote_current_version =>
			q{
				my $v = $this_track->monitor_version;
				promote_version_to_track($this_track, $v);
			},
		greet => 
			q{
				my ($name,$adjective) = @_;
				print ("Hello $name! You look $adjective today!!\n");
			},
	},

# __END__
# 

# Syntax notes:

# 0. Quick Start - To avoid breaking this file:
#
#   + Be careful of matching curly brackets {}. (Also [] () if you use them.)
#     All should be properly paired.
#
#   + Closing brackets are usually followed by a comma, i.e,
#
#          key => q{ some 
#                    various
#                    stuff
#           }, 
#
# 
# 1. The => Operator
# 
#     The => operator is similar to the comma ",". It
#     is used to indicate a key-value pair, i.e.
#   
#          greeting => 'hello earthlings!',
#   
#          pi       => 3.14,
#   
# 2. The q{..} Notation
# 
#     The q{.....} notation is a kind of quoting, like "....."
#     It is special, in that it can contain quotes without choking i.e.
#   
#          q{"here is a message", "john","marilyn",'single'}
# 
# 3. Curly braces { }
# 
#     The outermost curly braces combine the following
#     commands and their defintions into a single
#     data structure called a 'hash' or 'dictionary'
# 
#          command => { magic_mix => q{ user code },
#                       death_ray => q{ more user code},
#                      }
# 
# (end of file)

__[default_palette_yml]__
---
namapalette:
  Capture: #f22c92f088d3
  ClockBackground: #998ca489b438
  ClockForeground: #000000000000
  GroupBackground: #998ca489b438
  GroupForeground: #000000000000
  MarkArmed: #d74a811f443f
  Mixdown: #bf67c5a1491f
  MonBackground: #9420a9aec871
  MonForeground: Black
  Mute: #a5a183828382
  OffBackground: #998ca489b438
  OffForeground: Black
  Play: #68d7aabf755c
  RecBackground: #d9156e866335
  RecForeground: Black
  SendBackground: #9ba79cbbcc8a
  SendForeground: Black
  SourceBackground: #f22c92f088d3
  SourceForeground: Black
palette:
  ew:
    background: #d915cc1bc3cf
    foreground: black
  mw:
    activeBackground: #81acc290d332
    background: #998ca489b438
    foreground: black
...

__[fake_jack_lsp]__
system:capture_1
   alsa_pcm:capture_1
	properties: output,can-monitor,physical,terminal,
system:capture_2
   alsa_pcm:capture_2
	properties: output,can-monitor,physical,terminal,
system:capture_3
   alsa_pcm:capture_3
	properties: output,can-monitor,physical,terminal,
system:capture_4
   alsa_pcm:capture_4
	properties: output,can-monitor,physical,terminal,
system:capture_5
   alsa_pcm:capture_5
	properties: output,can-monitor,physical,terminal,
system:capture_6
   alsa_pcm:capture_6
	properties: output,can-monitor,physical,terminal,
system:capture_7
   alsa_pcm:capture_7
	properties: output,can-monitor,physical,terminal,
system:capture_8
   alsa_pcm:capture_8
	properties: output,can-monitor,physical,terminal,
system:capture_9
   alsa_pcm:capture_9
	properties: output,can-monitor,physical,terminal,
system:capture_10
   alsa_pcm:capture_10
	properties: output,can-monitor,physical,terminal,
system:capture_11
   alsa_pcm:capture_11
	properties: output,can-monitor,physical,terminal,
system:capture_12
   alsa_pcm:capture_12
	properties: output,can-monitor,physical,terminal,
system:playback_1
   alsa_pcm:playback_1
	properties: input,physical,terminal,
system:playback_2
   alsa_pcm:playback_2
	properties: input,physical,terminal,
system:playback_3
   alsa_pcm:playback_3
	properties: input,physical,terminal,
system:playback_4
   alsa_pcm:playback_4
	properties: input,physical,terminal,
system:playback_5
   alsa_pcm:playback_5
	properties: input,physical,terminal,
system:playback_6
   alsa_pcm:playback_6
	properties: input,physical,terminal,
system:playback_7
   alsa_pcm:playback_7
	properties: input,physical,terminal,
system:playback_8
   alsa_pcm:playback_8
	properties: input,physical,terminal,
system:playback_9
   alsa_pcm:playback_9
	properties: input,physical,terminal,
system:playback_10
   alsa_pcm:playback_10
	properties: input,physical,terminal,
Horgand:out_1
        properties: output,terminal,
Horgand:out_2
        properties: output,terminal,
fluidsynth:left
	properties: output,
fluidsynth:right
	properties: output,
ecasound:out_1
	properties: output,
ecasound:out_2
	properties: output,
LinuxSampler:0
	properties: output,
LinuxSampler:1
	properties: output,
beatrix-0:output-0
	properties: output,
beatrix-0:output-1
	properties: output,

__[midish_commands]__
tracklist
tracknew
trackdelete
trackrename
trackexists
trackaddev
tracksetcurfilt
trackgetcurfilt
trackcheck
trackcut
trackblank
trackinsert
trackcopy
trackquant
tracktransp
trackmerge
tracksetmute
trackgetmute
trackchanlist
trackinfo
channew
chanset
chandelete
chanrename
chanexists
changetch
changetdev
chanconfev
chanunconfev
chaninfo
chansetcurinput
changetcurinput
filtnew
filtdelete
filtrename
filtexists
filtreset
filtinfo
filtsetcurchan
filtgetcurchan
filtchgich
filtchgidev
filtswapich
filtswapidev
filtchgoch
filtchgodev
filtswapoch
filtswapodev
filtdevdrop
filtnodevdrop
filtdevmap
filtnodevmap
filtchandrop
filtnochandrop
filtchanmap
filtnochanmap
filtctldrop
filtnoctldrop
filtctlmap
filtnoctlmap
filtkeydrop
filtnokeydrop
filtkeymap
filtnokeymap
sysexnew
sysexdelete
sysexrename
sysexexists
sysexclear
sysexsetunit
sysexadd
sysexinfo
songidle
songplay
songrecord
sendraw
songsetcurquant
songgetcurquant
songsetcurpos
songgetcurpos
songsetcurlen
songgetcurlen
songsetcurtrack
songgetcurtrack
songsetcurfilt
songgetcurfilt
songsetcursysex
songgetcursysex
songsetcurchan
songgetcurchan
songsetcurinput
changetcurinput
songsetunit
songgetunit
songsetfactor
songgetfactor
songsettempo
songtimeins
songtimerm
songtimeinfo
songinfo
songsave
songload
songreset
songexportsmf
songimportsmf
devlist
devattach
devdetach
devsetmaster
devgetmaster
devsendrt
devticrate
devinfo
devixctl
devoxctl
ctlconf
ctlconfx
ctlconf
ctlinfo
metroswitch
metroconf
info
print
exec
debug
panic
let
proc

__[end_data_section]__
__END__

=head1 NAME

Nama (Audio::Nama) - an audio recording, mixing and editing application

=head1 DESCRIPTION

B<Nama> is an application for multitrack recording,
non-destructive editing, mixing and mastering using the
Ecasound audio engine developed by Kai Vehmanen.

Features include tracks, buses, effects, presets,
sends, inserts, marks and regions. Nama runs under JACK and
ALSA audio frameworks, automatically detects LADSPA plugins,
and supports Ladish Level 1 session handling.

Type C<man nama> for details.