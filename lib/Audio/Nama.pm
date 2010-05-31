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
$VERSION = 1.058;
use Modern::Perl;
#use Carp::Always;
no warnings qw(uninitialized syntax);
use autodie qw(:default);
use Carp;
use Cwd;
use File::Find::Rule;
use File::Spec::Link;
use File::Path;
use File::Spec;
use File::Temp;
use Getopt::Long;
use IO::All;
use IO::Socket; 
use Module::Load::Conditional qw(can_load); 
use Parse::RecDescent;
use Storable; 
use Term::ReadLine;
use Graph;
use Data::Section -setup;
# use Timer::HiRes; # automatically detected
# use Tk;           # loaded conditionally
# use Event;		# loaded conditionally
# use AnyEvent;		# loaded after Tk or Event
# use Tk::FontDialog; # hmmm might be nice to use
use Text::Format;

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

## Definitions ##

$| = 1;     # flush STDOUT buffer on every write

# 'our' declaration: code in all packages in Nama.pm can address
# the following variables without package name prefix

our (

    # 'our' means these variables will be accessible, without
	# package qualifiers, to all packages inhabiting 
	# the same file.
	#
	# this allows us to bring our variables from 
    # procedural core into Audio::Nama::Graphical and Audio::Nama::Text
	# packages. 
	
	# it didn't work out to be as helpful as i'd like
	# because the grammar requires package path anyway

	$banner,
	$help_screen, 		# 
	@help_topic,    # array of help categories
	%help_topic,    # help text indexed by topic
	$use_pager,     # display lengthy output data using pager
	$use_placeholders,  # use placeholders in show_track output
	$text_wrap,          # Text::Format object

	$ui, # object providing class behavior for graphic/text functions

	@persistent_vars, # a set of variables we save
					  	# as one big config file
	@effects_static_vars,	# the list of which variables to store and retrieve
	@effects_dynamic_vars,		# same for all chain operators
	@config_vars,    # contained in config file
	%abbreviations, # for replacements in config files

	$ecasound_globals_realtime,     # .namarc field
	$ecasound_globals_default,  # .namarc field
	$ecasound_tcp_port,  # for Ecasound NetECI interface
	$saved_version, # copy of $VERSION saved with settings in State.yml


	$default,		# the internal default configuration file, as string
	$default_palette_yml, # default GUI colors
					
	$raw_to_disk_format,
	$mix_to_disk_format,
	$cache_to_disk_format,
	$mixer_out_format,
	$execute_on_project_load, # Nama text commands 
	$use_group_numbering, # same version number for tracks recorded together

	# .namarc mastering fields
    $mastering_effects, # apply on entering mastering mode
	$volume_control_operator,
	$eq, 
	$low_pass,
	$mid_pass,
	$high_pass,
	$compressor,
	$spatialiser,
	$limiter,

	$initial_user_mode, # preview, doodle, 0, undef TODO
	
	%state_c_ops, 	# intermediate copy for storage/retrieval
	$effects_cache_file, # where we keep info on Ecasound
					# and LADSPA effects, presets, etc.
	
	$ecasound, 		# the name to invoke when we want to kill ecasound

	$grammar, 		# filled by Grammar.pm
	$parser,		# for the objected created by Parse::RecDescent
	%iam_cmd,		# for identifying IAM commands in user input
	@nama_commands,# array of commands my functions provide
	%nama_commands,# as hash as well
	$project_root,	

					# Nama directory structure and files

					# ~/.namarc						# config file
					# ~/nama/untitled				# project directory
					# ~/nama/untitled/.wav			# wav directory
					# ~/nama/untitled/State.yml		# project state
					# ~/nama/untitled/Setup.ecs		# Ecasound chain setup
					# ~/nama/.effects_cache			# static effects data
					# ~/nama/effect_chains			# Nama effect presets
					# ~/nama/effect_profiles		# Nama effect profiles

	$state_store_file,	# filename for storing @persistent_vars
	$effect_chain_file, # for storing effect chains
	$effect_profile_file, # for storing effect templates
	$chain_setup_file, # Ecasound uses this 

	$soundcard_channels,# channel selection range 
	$tk_input_channels,# alias for above
	                # on the menubutton
	%cfg,        # 'config' information as hash
	%devices, 		# alias to data in %cfg
	%opts,          # command line options
	%oid_status,    # state information for the chain templates
	$use_monitor_version_for_mixdown, # sync mixdown version numbers
	              	# to selected track versions , not
					# implemented
	$this_track,	 # the currently active track -- 
					 # used by Text UI only at present
	$this_track_name, # for save/restore 
	$old_this_track, # when we need to remember previous setting
	$this_op,      # currently selected effect # future
	$this_mark,    # current mark  # for future
	$this_bus, 		# current bus

	@format_fields, # data for replies to text commands

	$project,		# variable for GUI text input
	$project_name,	# current project name
	%state_c,		# for backwards compatilility

	### for effects

	$cop_id, 		# chain operator id, that how we create, 
					# store, find them, adjust them, and destroy them,
					# per track or per project?
	$magical_cop_id, # cut through five levels of subroutines
	%cops,			 # chain operators stored here
	%copp,			# their parameters for effect update
	%copp_exp,      # for log-scaled sliders

# auxiliary track information - saving not required

	%offset,        # index by chain, offset for user-visible effects 
	@mastering_effect_ids,        # effect ids for mastering mode

	@effects,		# static effects information (parameters, hints, etc.)
	%effect_i,		# an index , pn:amp -> effect number
	%effect_j,      # an index , amp -> effect number
	@effects_help,  # one line per effect, for text search

	@ladspa_sorted, # ld
	%effects_ladspa, # parsed data from analyseplugin 
	%effects_ladspa_file, 
					# get plugin filename from Plugin Unique ID
	%ladspa_unique_id, 
					# get plugin unique id from plugin label
	%ladspa_label,  # get plugin label from unique id
	%ladspa_help,   # plugin_label => analyseplugin output
	$e,				# the name of the variable holding
					# the Ecasound engine object.
					
	%e_bound,		# for displaying hundreds of effects in groups
	$unit,			# jump multiplier, 1 or 60 seconds
	%old_vol,		# a copy of volume settings, for muting
	$length,		# maximum duration of the recording/playback if known
 	$jack_system,   # jack soundcard device
	$jack_running,  # jackd status (pid)
	$jack_lsp,      # jack_lsp -Ap
	$fake_jack_lsp, # for testing
	%jack,			# jack clients data from jack_lsp

	@input_chains,	# list of input chain segments 
	@output_chains, # list of output chain segments
	@post_input,	# post-input chain operators
	@pre_output, 	# pre-output chain operators

	%subst,			# alias, substitutions for the config file
	$tkeca_effects_data,	# original tcl code, actually

	### Widgets
	
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

	@oids,	# output templates, are applied to the
			# chains collected previously
			# the results are grouped as
			# input, output and intermediate sections

	%inputs,
	%outputs,
	%post_input,
	%pre_output,

	$ladspa_sample_rate,	# used as LADSPA effect parameter fixed at 44100

	$track_name,	# received from Tk text input form
	%track_names,   # belongs in Track.pm
	$ch_r,			# recording channel assignment
	$ch_m,			# monitoring channel assignment


	%L,	# for effects
	%M,
	$debug,				# debug level flags for diagnostics
	$debug2,			# for subroutine names as execute
	$debug3,			# deprecated
						
	$OUT,				# filehandle for Text mode print
	#$commands,	# ref created from commands.yml
	%commands,	# created from commands.yml
	$commands_yml, # the string form of commands.yml
	$cop_hints_yml, # ecasound effects hinting

	$save_id, # text variable
	$sn_save_text,# text entry widget
	$sn_save,	# button to save settings
	$sn_recall,	# button to recall settings

	# new object core
	
	$main_bus, 
	$main, # main group
	$null_bus,
    $null, # null group

	%ti, # track by index (alias %Audio::Nama::Track::by_index)
	%tn, # track by name  (alias %Audio::Nama::Track::by_name)

	@tracks_data, # staging for saving
	@groups_data, # obsolete
	@marks_data,  # for storage
	@inserts_data, # for storage
	@bus_data,    # 
	@fade_data, #
	@system_buses, # 
	%is_system_bus, # 

	$alsa_playback_device,
	$alsa_capture_device,

	$main_out, # boolean: route audio output to soundcard?

	# mastering mode status

	$mastering_mode,

   # marks and playback looping
   
	$clock_id,		# used in GUI for the Tk event system
					# ->cancel method not reliable
					# for 'repeat' events, so converted to
					# 'after' events
	%event_id,    # events will store themselves with a key
	@loop_endpoints, # they define the loop
	$loop_enable, # whether we automatically loop

   $previous_text_command, # i want to know if i'm repeating
	$term, 			# Term::ReadLine object
	$controller_ports, # where we listen for MIDI messages
    $midi_inputs,  # on/off/capture

	@already_muted, # for soloing list of Track objects that are 
                    # muted before we begin
    $soloing,       # one user track is on, all others are muted

	%bunch,			# user collections of tracks
	@keywords,      # for autocompletion
	$attribs,       # Term::Readline::Gnu object
	$seek_delay,    # allow microseconds for transport seek
                    # (used with JACK only)
    $prompt,        # for text mode
	$preview,       # am running engine with rec_file disabled
	%duplicate_inputs, # named tracks will be OFF in doodle mode
	%already_used,  #  source => used_by
	$memoize,       # do I cache this_wav_dir?
	$hires,        # do I have Timer::HiRes?
	$fade_time, 	# duration for fadein(), fadeout()
	$old_snapshot,  # previous status_snapshot() output
					# to check if I need to reconfigure engine
	$old_group_rw, # previous $main->rw setting
	%old_rw,       # previous track rw settings (indexed by track name)
	
	@mastering_track_names, # reserved for mastering mode
	@command_history,
	$disable_auto_reconfigure, # for debugging

	$g, 			# Graph var, for chain setup
	%cooked_record_pending, # an intermediate mixdown for tracks
	$press_space_to_start_transport, #  in text mode
	%effect_chain, # named effect sequences
	%effect_profile, # effect chains for multiple tracks
	$sock, 			# socket for Net-ECI mode
	%versions,		# store active versions for use after engine run
	@io, 			# accumulate IO objects for generating setup
	$track_snapshots, # to save recalculating for each IO object
	$chain_setup,	# current chain setup
	%mute_level,	# 0 for ea as vol control, -127 for eadb
	%fade_out_level, # 0 for ea, -40 for eadb
	$fade_resolution, # steps per second
	%unity_level,	# 100 for ea, 0 for eadb
	
	$default_fade_length, 
	$regenerate_setup, # force us to generate new chain setup
	%is_ecasound_chain,   # suitable for c-select
);
 

# variables found in namarc
#
@config_vars = qw(
						%abbreviations
						%devices
						$ecasound_globals_realtime
						$ecasound_globals_default
						$ecasound_tcp_port
						$mix_to_disk_format
						$raw_to_disk_format
						$cache_to_disk_format
						$mixer_out_format
						$alsa_playback_device
						$alsa_capture_device	
						$soundcard_channels
						$project_root 	
						$use_group_numbering
						$press_space_to_start_transport
						$execute_on_project_load
						$initial_user_mode
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

						
						
# used for saving to State.yml
#
@persistent_vars = qw(

						%cops 			
						$cop_id 		
						%copp 			
						%copp_exp
						$unit			
						%oid_status		
						%old_vol		
						$this_op
						@tracks_data
						@bus_data
						@groups_data
						@marks_data
						@fade_data
						@inserts_data
						$loop_enable
						@loop_endpoints
						$length
						%bunch
						$mastering_mode
						@command_history
						$saved_version
						$main_out
						$this_track_name
						);
					 
# used for effects_cache 
#
@effects_static_vars = qw(

						@effects		
						%effect_i	
						%effect_j	
						%e_bound
						@ladspa_sorted
						%effects_ladspa	
						%effects_ladspa_file
						%ladspa_unique_id
						%ladspa_label
						%ladspa_help
						@effects_help
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
    /    Nama multitrack recorder v. $VERSION (c)2008-2009 Joel Roth     /
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
$fade_time = 0.3;
$old_snapshot = {};
$main_out = 1; # enable main output
$this_bus = 'Main';
jack_update(); # to be polled by Event
$memoize = 1;
$volume_control_operator = 'ea'; # don't break Stephanie's system
%mute_level 	= (ea => 0, 	eadb => -96); 
%fade_out_level = (ea => 0, 	eadb => -40);
%unity_level 	= (ea => 100, 	eadb => 0); 
$fade_resolution = 200; # steps per second
$default_fade_length = 0.5;

@mastering_track_names = qw(Eq Low Mid High Boost);
$mastering_mode = 0;

init_memoize() if $memoize;

# aliases for concise access

*tn = \%Audio::Nama::Track::by_name;
*ti = \%Audio::Nama::Track::by_index;
# $ti{3}->rw
sub setup_grammar { 
}
	### COMMAND LINE PARSER 

	$debug2 and print "Reading grammar\n";

	*commands_yml = __PACKAGE__->section_data("commands_yml");
	*cop_hints_yml = __PACKAGE__->section_data("chain_op_hints_yml");
	%commands = %{ Audio::Nama::yaml_in( $Audio::Nama::commands_yml) };

	$Audio::Nama::AUTOSTUB = 1;
	$Audio::Nama::RD_TRACE = 1;
	$Audio::Nama::RD_ERRORS = 1; # Make sure the parser dies when it encounters an error
	$Audio::Nama::RD_WARN   = 1; # Enable warnings. This will warn on unused rules &c.
	$Audio::Nama::RD_HINT   = 1; # Give out hints to help fix problems.

	*grammar = __PACKAGE__->section_data("grammar");

	$parser = new Parse::RecDescent ($grammar) or croak "Bad grammar!\n";

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

   remove_track, rmt         - remove effects, parameters and GUI for current
                               track

   show_tracks, show, tracks -  show status of all tracks
                                and group settings

   show_track, sh            -  show status of current track,
                                including effects, versions, 
                                modifiers,  "sax; sh"

   stereo                    -  set track width to 2 channels

   mono                      -  set track width to 1 channel

   solo                      -  mute all tracks but current track

   all, nosolo               -  return to pre-solo status

 - channel inputs and outputs 

   source, src, r            -  set track source

                                sax r 3 (record from soundcard channel 3) 

                                organ r synth (record from JACK client "synth")

                             -  with no arguments returns current signal source

   send, out, m, aux         -  create an auxiliary send, argument 
                                can be channel number or JACK client name

                             -  currently one send allowed per track

                             -  not needed for most setups
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

   set_track, set          - directly set current track parameters

   destroy_current_wav     - unlink current track's selected WAV version.
                             Nama's only destructive command. USE WITH CARE!

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
                                         for cello violin bass; set bus Strings

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
HELP


	# we use the following settings if we can't find config files

	*default = __PACKAGE__->section_data("default_namarc");

	# default colors

	*default_palette_yml = __PACKAGE__->section_data("default_palette_yml");

	# JACK environment for testing

	*fake_jack_lsp = __PACKAGE__->section_data("fake_jack_lsp");

	# print remove_spaces("bulwinkle is a...");

#### Class and Object definitions for package 'Audio::Nama'

our @ISA; # no anscestors
use Audio::Nama::Object qw(mode);

## The following methods belong to the root class

sub hello {"superclass hello"}

sub new { my $class = shift; return bless {@_}, $class }

sub main { 
#	setup_grammar(); # executes directly in body
	process_options();
	prepare(); 
	command_process($execute_on_project_load);
	reconfigure_engine();
	command_process($opts{X});
	$ui->loop;
}
sub prepare {
	
	$debug2 and print "&prepare\n";
	choose_sleep_routine();

	$project_name = shift @ARGV;
	$debug and print "project name: $project_name\n";

	$debug and print ("\%opts\n======\n", yaml_out(\%opts)); ; 


	read_config(global_config());  # from .namarc if we have one

	select_ecasound_interface();

	$debug and print "reading config file\n";
	if ($opts{d}){
		print "found command line project_root flag\n";
		$project_root = $opts{d};
	}

	# capture the sample frequency from .namarc
	($ladspa_sample_rate) = $devices{jack}{signal_format} =~ /(\d+)(,i)?$/;

	# skip initializations if user (test) supplies project
	# directory
	
	first_run() unless $opts{d}; 

	prepare_static_effects_data() unless $opts{e};

	get_ecasound_iam_keywords();
	load_keywords(); # for autocompletion

	chdir $project_root # for filename autocompletion
		or warn "$project_root: chdir failed: $!\n";

	$ui->init_gui;
	$ui->transport_gui;
	$ui->time_gui;

	
	# fake JACK for testing environment

	%jack = %{ jack_ports($fake_jack_lsp) } ;
	$jack_running = 1 if $opts{J};

	# periodically check if JACK is running, and get client/port list

	poll_jack() unless $opts{J} or $opts{A};

	initialize_terminal();

	# set default project to "untitled"
	
	if (! $project_name ){
		$project_name = "untitled";
		$opts{c}++; 
	}
	print "\nproject_name: $project_name\n";
	
	load_project( name => $project_name, create => $opts{c}) ;
	restore_effect_chains();
	restore_effect_profiles();
	1;	
}
sub issue_first_prompt {
	$term->stuff_char(10); # necessary to respond to Ctrl-C at first prompt 
	&{$attribs->{'callback_read_char'}}();
	set_current_bus();
	print prompt();
	$attribs->{already_prompted} = 0;
}

sub select_ecasound_interface {
	return if $opts{E} or $opts{A};
	if ( can_load( modules => { 'Audio::Ecasound' => undef } )
			and ! $opts{n} ){ 
		say "\nUsing Ecasound via Audio::Ecasound (libecasoundc).";
		{ no warnings qw(redefine);
		*eval_iam = \&eval_iam_libecasoundc; }
		$e = Audio::Ecasound->new();
	} else { 

		no warnings qw(redefine);
		launch_ecasound_server($ecasound_tcp_port);
		init_ecasound_socket($ecasound_tcp_port); 
		*eval_iam = \&eval_iam_neteci;
	}
}
	


sub choose_sleep_routine {
	if ( can_load(modules => {'Time::HiRes'=> undef} ) ) 
		 { *sleeper = *finesleep;
			$hires++; }
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


sub initialize_terminal {
	$term = new Term::ReadLine("Ecasound/Nama");
	$attribs = $term->Attribs;
	$attribs->{attempted_completion_function} = \&complete;
	$attribs->{already_prompted} = 1;
	vet_keystrokes();
	revise_prompt();
	# handle Control-C from terminal

	$SIG{INT} = \&cleanup_exit;
	$SIG{USR1} = sub { save_state() };
	#$event_id{sigint} = AE::signal('INT', \&cleanup_exit);

}
sub revise_prompt {
    $term->callback_handler_install(prompt(), \&process_line);
}
sub prompt {
	"nama [". ($this_bus eq 'Main' ? '': "$this_bus/").  
		($this_track ? $this_track->name : '') . "] ('h' for help)> "
}
sub vet_keystrokes {
	$event_id{stdin} = AE::io(*STDIN, 0, sub {
		&{$attribs->{'callback_read_char'}}();
		if (  $press_space_to_start_transport and
				$attribs->{line_buffer} eq " " ){

			toggle_transport();	
			$attribs->{line_buffer} = q();
			$attribs->{point} 		= 0;
			$attribs->{end}   		= 0;
			$term->stuff_char(10);
			&{$attribs->{'callback_read_char'}}();
		}
	});
}
	
sub toggle_transport {
	if (engine_running()){ stop_transport() } 
	else { start_transport() }
}
	
sub first_run {
	return if $opts{f};
	my $config = config_file();
	$config = "$ENV{HOME}/$config" unless -e $config;
	$debug and print "config: $config\n";
	if ( ! -e $config and ! -l $config  ) {

	# check for missing components

	my $missing;
	my @a = `which analyseplugin`;
	@a or print ( <<WARN
LADSPA helper program 'analyseplugin' not found
in $ENV{PATH}, your shell's list of executable 
directories. You will probably have more fun with the LADSPA
libraries and executables installed. http://ladspa.org
WARN
	) and  sleeper (0.6) and $missing++;
	my @b = `which ecasound`;
	@b or print ( <<WARN
Ecasound executable program 'ecasound' not found
in $ENV{PATH}, your shell's list of executable 
directories. This suite depends on the Ecasound
libraries and executables for all audio processing! 
WARN
	) and sleeper (0.6) and $missing++;
	if ( $missing ) {
	print "You lack $missing main parts of this suite.  
Do you want to continue? [N] ";
	$missing and 
	my $reply = <STDIN>;
	chomp $reply;
	print ("Goodbye.\n"), exit unless $reply =~ /y/i;
	}
print <<HELLO;

Aloha. Welcome to Nama and Ecasound.

HELLO
	sleeper (0.6);
	print "Configuration file $config not found.

May I create it for you? [yes] ";
	my $make_namarc = <STDIN>;
	sleep 1;
	print <<PROJECT_ROOT;

Nama places all sound and control files under the
project root directory, by default $ENV{HOME}/nama.

PROJECT_ROOT
	print "Would you like to create $ENV{HOME}/nama? [yes] ";
	my $reply = <STDIN>;
	chomp $reply;
	if ($reply !~ /n/i){
		$default =~ s/^project_root.*$/project_root: $ENV{HOME}\/nama/m;
		mkpath( join_path($ENV{HOME}, qw(nama untitled .wav)) );
	} else {
		print <<OTHER;
Please make sure to set the project_root directory in
.namarc, or on the command line using the -d option.

OTHER
	}
	if ($make_namarc !~ /n/i){
		$default > io( $config );
	}
	sleep 1;
	print "\n.... Done!\n\nPlease edit $config and restart Nama.\n\n";
	print "Exiting.\n"; 
	exit;	
	}
}

sub process_options {

	my %options = qw(

        save-alsa  		a
		project-root=s  d
		create-project  c
		config=s		f
		gui			  	g
		text			t
		no-state		m
		net-eci			n
		libecasoundc	l
		help			h
		regenerate-effects-cache	r
		no-static-effects-data		s
		no-static-effects-cache		e
		no-reconfigure-engine		R
		fake-jack					J
		fake-alsa					A
		fake-ecasound				E
		debugging-output			D
		execute-command=s			X
);

	map{$opts{$_} = ''} values %options;

	# long options

	Getopt::Long::Configure ("bundling");	
	my $getopts = 'GetOptions( ';
	map{ $getopts .= qq("$options{$_}|$_" => \\\$opts{$options{$_}}, \n)} keys %options;
	$getopts .= ' )' ;

	#say $getopts;

	eval $getopts or die "Stopped.\n";
	
	if ($opts{h}){
	say <<HELP; exit; }

USAGE: nama [options] [project_name]

--gui, -g                        Start Nama in GUI mode
--text, -t                       Start Nama in text mode
--config, -f                     Specify configuration file (default: ~/.namarc)
--project-root, -d               Specify project root directory
--create-project, -c             Create project if it doesn't exist
--net-eci, -n                    Use Ecasound's Net-ECI interface
--libecasoundc, -l               Use Ecasound's libecasoundc interface
--save-alsa, -a                  Save/restore alsa state with project data
--help, -h                       This help display

Debugging options:

--no-static-effects-data, -s     Don't load effects data
--no-state, -m                   Don't load project state
--no-static-effects-cache, -e    Bypass effects data cache
--regenerate-effects-cache, -r   Regenerate the effects data cache
--no-reconfigure-engine, -R      Don't automatically configure engine
--debugging-output, -D           Emit debugging information
--fake-jack, -J                  Simulate JACK environment
--fake-alsa, -A                  Simulate ALSA environment
--no-ecasound, -E                Don't spawn Ecasound process
--execute-command, -X            Supply a command to execute

HELP

#--no-ecasound, -E                Don't load Ecasound (for testing)

	say $banner;

	if ($opts{D}){
		$debug = 1;
		$debug2 = 1;
	}
	if ( ! $opts{t} and can_load( modules => { Tk => undef } ) ){ 
		$ui = Audio::Nama::Graphical->new;
	} else {
		$ui = Audio::Nama::Text->new;
		can_load( modules =>{ Event => undef})
			or die "Perl Module 'Event' not found. Please install it and try again. Stopping.";
;
		import Event qw(loop unloop unloop_all);
	}
	can_load( modules => {AnyEvent => undef})
			or die "Perl Module 'AnyEvent' not found. Please install it and try again. Stopping.";

}
	
{
my $default_port = 2868; # Ecasound's default
sub launch_ecasound_server {

	# we'll try to communicate with an existing ecasound
	# process provided:
	#
	# started with --server option
	# --server-tcp-port option matches --or--
	# nama is using Ecasound's default port 2868
	
	my $port = shift // $default_port;
	my $command = "ecasound -K -C --server --server-tcp-port=$port";
	my $redirect = "2>&1>/dev/null &";
	my $ps = qx(ps ax);
	say ("Using existing Ecasound server"), return 
		if  $ps =~ /ecasound/
		and $ps =~ /--server/
		and ($ps =~ /tcp-port=$port/ or $port == $default_port);
	say "Starting Ecasound server";
 	system("$command $redirect") == 0 or carp "system $command failed: $?\n";
	sleep 1;
}


sub init_ecasound_socket {
	my $port = shift // $default_port;
	say "Creating socket on port $port.";
	$sock = new IO::Socket::INET (
		PeerAddr => 'localhost', 
		PeerPort => $port, 
		Proto => 'tcp', 
	); 
	die "Could not create socket: $!\n" unless $sock; 
}

sub ecasound_pid {
	my ($ps) = grep{ /ecasound/ and /server/ } qx(ps ax);
	my ($pid) = split " ", $ps; 
	$pid if $sock; # conditional on using socket i.e. Net-ECI
}

sub eval_iam { } # stub

sub eval_iam_neteci {
	my $cmd = shift;
	$cmd =~ s/\s*$//s; # remove trailing white space
	$sock->send("$cmd\r\n"); 
	my $buf;
	$sock->recv($buf, 65536);

	my ($return_value, $length, $type, $reply) =
		$buf =~ /(\d+)# digits
				 \    # space
				 (\d+)# digits
				 \    # space
 				 ([^\r\n]+) # a line of text, probably one character 
				\r\n    # newline
				(.+)  # rest of string
				/sx;  # s-flag: . matches newline

$debug and say "iam: $cmd";
$debug and say "return value: $return_value
length: $length
type: $type
reply: $reply";

	$return_value == 256 or die "illegal return value, stopped" ;
	$reply =~ s/\s+$//; 

	given($type){
		when ('e'){ warn $reply }
		default{ return $reply }
	}

}
}

sub eval_iam_libecasoundc{
	#$debug2 and print "&eval_iam\n";
	my $command = shift;
	$debug and print "iam command: $command\n";
	my (@result) = $e->eci($command);
	$debug and print "result: @result\n" unless $command =~ /register/;
	my $errmsg = $e->errmsg();
	# $errmsg and carp("IAM WARN: ",$errmsg), 
	# not needed ecasound prints error on STDOUT
	$e->errmsg('');
	"@result";
	#$errmsg ? undef : "@result";
}
sub initialize_ecasound_engine {
	eval_iam('cs-disconnect') if eval_iam('cs-connected');
	eval_iam('cs-remove') if eval_iam('cs-selected');
}
sub colonize { # convert seconds to hours:minutes:seconds 
	my $sec = shift || 0;
	my $hours = int ($sec / 3600);
	$sec = $sec % 3600;
	my $min = int ($sec / 60);
	$sec = $sec % 60;
	$sec = "0$sec" if $sec < 10;
	$min = "0$min" if $min < 10 and $hours;
	($hours ? "$hours:" : "") . qq($min:$sec);
}

## configuration file
{ # OPTIMIZATION
my %proot; 
sub project_root { $proot{$project_root} ||= 
		File::Spec::Link->resolve_all(expand_tilde($project_root))}
}

sub config_file { $opts{f} ? $opts{f} : ".namarc" }
{ # OPTIMIZATION
my %wdir; 
sub this_wav_dir {
	$project_name and
	$wdir{$project_name} ||= File::Spec::Link->resolve_all(
		join_path( project_root(), $project_name, q(.wav) )  
	);
}
}

sub project_dir  {$project_name and join_path( project_root(), $project_name) }

sub expand_tilde { my $path = shift; $path =~ s/~/$ENV{HOME}/; $path }


sub global_config{
print ("reading config file $opts{f}\n"), return io( $opts{f})->all if $opts{f} and -r $opts{f};
my @search_path = (project_dir(), $ENV{HOME}, project_root() );
my $c = 0;
	map{ 
#print $/,++$c,$/;
			if (-d $_) {
				my $config = join_path($_, config_file());
				#print "config: $config\n";
				if( -f $config ){ 
					my $yml = io($config)->all ;
					return $yml;
				}
			}
		} ( @search_path) 
}

sub read_config {
	$debug2 and print "&read_config\n";
	
	my $config = shift;
	my $yml = length $config > 100 ? $config : $default;
	strip_all( $yml );
	%cfg = %{  yaml_in($yml) };
	*subst = \%{ $cfg{abbreviations} }; # alias
	walk_tree(\%cfg);
	walk_tree(\%cfg); # second pass completes substitutions
	assign_var( \%cfg, @config_vars);
	$project_root = $opts{d} if $opts{d};

}
sub walk_tree {
	#$debug2 and print "&walk_tree\n";
	my $ref = shift;
	map { substitute($ref, $_) } 
		grep {$_ ne q(abbreviations)} 
			keys %{ $ref };
}
sub substitute{
	my ($parent, $key)  = @_;
	my $val = $parent->{$key};
	#$debug and print qq(key: $key val: $val\n);
	ref $val and walk_tree($val)
		or map{$parent->{$key} =~ s/$_/$subst{$_}/} keys %subst;
}
## project handling

sub list_projects {
	my $projects = join "\n", sort map{
			my ($vol, $dir, $lastdir) = File::Spec->splitpath($_); $lastdir
		} File::Find::Rule  ->directory()
							->maxdepth(1)
							->extras( { follow => 1} )
						 	->in( project_root());
	pager($projects);
}
sub list_plugins {}
		
sub load_project {
	$debug2 and print "&load_project\n";
	my %h = @_;
	$debug and print yaml_out \%h;
	print ("no project name.. doing nothing.\n"),return 
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
	
	initialize_ecasound_engine(); 
	initialize_buses();	
	initialize_project_data();
	remove_small_wavs(); 
	rememoize();

	restore_state( $h{settings} ? $h{settings} : $state_store_file) unless $opts{m} ;
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


	$opts{m} = 0; # enable 
	
	dig_ruins() unless scalar @Audio::Nama::Track::all > 2;

	# possible null if Text mode
	
	$ui->global_version_buttons(); 
	$ui->refresh_group;

	$debug and print "project_root: ", project_root(), $/;
	$debug and print "this_wav_dir: ", this_wav_dir(), $/;
	$debug and print "project_dir: ", project_dir() , $/;

 1;
}	
BEGIN { # OPTMIZATION
my @wav_functions = qw(
	get_versions 
	candidates 
	targets 
	versions 
	last 
);
my @track_functions = qw(
	dir 
	basename 
	full_path 
	group_last 
	last 
	current_wav 
	full_wav_path 
	current_version 
	monitor_version 
	maybe_monitor 
	rec_status 
	region_start_time 
	region_end_time 
	playat_time 
	fancy_ops 
	input_path 
);
sub track_memoize { # before generate_setup
	return unless $memoize;
	map{package Audio::Nama::Track; memoize($_) } @track_functions;
}
sub track_unmemoize { # after generate_setup
	return unless $memoize;
	map{package Audio::Nama::Track; unmemoize ($_)} @track_functions;
}
sub rememoize {
	return unless $memoize;
	map{package Audio::Nama::Wav; unmemoize ($_); memoize($_) } 
		@wav_functions;
}
sub init_memoize {
	return unless $memoize;
	map{package Audio::Nama::Wav; memoize($_) } @wav_functions;
}
}
sub jack_running {
	my @pids = split " ", qx(pgrep jackd);
	my @jack  = grep{   my $pid;
						/jackd/ and ! /defunct/
						and ($pid) = /(\d+)/
						and grep{ $pid == $_ } @pids 
				} split "\n", qx(ps ax) ;
}
sub engine_running {
	eval_iam("engine-status") eq "running"
};

sub initialize_buses {
	Audio::Nama::Bus->initialize();
	$main_bus = Audio::Nama::Bus->new(name => 'Main');
}
	
sub initialize_project_data {
	$debug2 and print "&initialize_project_data\n";

	return if transport_running();
	$ui->destroy_widgets();
	$ui->project_label_configure(
		-text => uc $project_name, 
		-background => 'lightyellow',
		); 

	# assign_var($project_init_file, @project_vars);

	%cops        = ();   
	$cop_id           = "A"; # autoincrement
	%copp           = ();    # chain operator parameters, dynamic
	                        # indexed by {$id}->[$param_no]
							# and others
	%old_vol = ();

	@input_chains = ();
	@output_chains = ();

	%track_widget = ();
	%effects_widget = ();

	# time related
	
	$markers_armed = 0;

	# new Marks
	# print "original marks\n";
	#print join $/, map{ $_->time} Audio::Nama::Mark::all();
 	map{ $_->remove} Audio::Nama::Mark::all();
	@marks_data = ();
	#print "remaining marks\n";
	#print join $/, map{ $_->time} Audio::Nama::Mark::all();
	# volume settings
	
	%old_vol = ();

	# $is_armed = 0;
	
	$old_snapshot = {};
	$preview = $initial_user_mode;
	$mastering_mode = 0;
	$saved_version = 0; 
	
	%bunch = ();	
	
	Audio::Nama::Bus->initialize();
	create_system_buses();
	$this_bus = 'Main';
	Audio::Nama::Track->initialize();

	%inputs = %outputs = ();

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

	$main = $Audio::Nama::Bus::by_name{Main};
	$null = $Audio::Nama::Bus::by_name{null};
}

## track and wav file handling

# create read-only track pointing at WAV files of specified
# track name in a different project

sub add_track_alias_project {
	my ($name, $track, $project) = @_;
	my $dir =  join_path(project_root(), $project, '.wav'); 
	if ( -d $dir ){
		if ( glob "$dir/$track*.wav"){
			print "Found target WAV files.\n";
			my @params = (target => $track, project => $project);
			add_track( $name, @params );
		} else { print "No WAV files found.  Skipping.\n"; return; }
	} else { 
		print("$project: project does not exist.  Skipping.\n");
		return;
	}
}

sub discard_object {
	shift @_ if (ref $_[0]) =~ /Nama/;
	@_;
}

# usual track

sub add_track {

	@_ = discard_object(@_);
	$debug2 and print "&add_track\n";
	#return if transport_running();
	my ($name, @params) = @_;
	$debug and print "name: $name, ch_r: $ch_r, ch_m: $ch_m\n";
	my $track = Audio::Nama::Track->new(
		name => $name,
		@params
	);
	return if ! $track; 
	$this_track = $track;
	$debug and print "ref new track: ", ref $track; 
	$track->source($ch_r) if $ch_r;
#		$track->send($ch_m) if $ch_m;

	my $group = $Audio::Nama::Bus::by_name{$track->group}; 
	command_process('for mon; mon') if $preview and $group->rw eq 'MON';
	$group->set(rw => 'REC') unless $track->target; # not if is alias

	# normal tracks default to 'REC'
	# track aliases default to 'MON'
	$track->set(rw => $track->target
					?  'MON'
					:  'REC') ;
	$track_name = $ch_m = $ch_r = undef;

	set_current_bus();
	$ui->track_gui($track->n);
	$debug and print "Added new track!\n", $track->dump;
}

# create read-only track pointing at WAV files of specified
# name in current project

sub add_track_alias {
	my ($name, $track) = @_;
	my $target; 
	if 		( $tn{$track} ){ $target = $track }
	elsif	( $ti{$track} ){ $target = $ti{$track}->name }
	add_track(  $name, target => $target );
}
sub add_slave_track {
	my %h = @_;
	say (qq[Group "$h{group}" does not exist, skipping.]), return
		 unless $Audio::Nama::Bus::by_name{$h{group}};
	say (qq[Target track "$h{target}" does not exist, skipping.]), return
		 unless $tn{$h{target}};
		Audio::Nama::SlaveTrack->new(	
			name => "$h{group}_$h{target}",
			target => $h{target},
			rw => 'MON',
			source_type => undef,
			source_id => undef,
			send_type => $Audio::Nama::Bus::by_name{$h{group}}->destination_type,
			send_id   => $Audio::Nama::Bus::by_name{$h{group}}->destination_id,
			)
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

sub remove_small_wavs {

	# 44 byte stubs left by a recording chainsetup that is 
	# connected by not started
	
	$debug2 and print "&remove_small_wavs\n";
	

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

sub add_volume_control {
	my $n = shift;
	return unless need_vol_pan($ti{$n}->name, "vol");
	
	my $vol_id = cop_add({
				chain => $n, 
				type => $volume_control_operator,
				cop_id => $ti{$n}->vol, # often undefined
				});
	
	$ti{$n}->set(vol => $vol_id);  # save the id for next time
	$vol_id;
}
sub add_pan_control {
	my $n = shift;
	return unless need_vol_pan($ti{$n}->name, "pan");

	my $pan_id = cop_add({
				chain => $n, 
				type => 'epp',
				cop_id => $ti{$n}->pan, # often undefined
				});
	
	$ti{$n}->set(pan => $pan_id);  # save the id for next time
	$pan_id;
}

# not used at present. we are probably going to offset the playat value if
# necessary

sub add_latency_compensation {
	print('LADSPA L/C/R Delay effect not found.
Unable to provide latency compensation.
'), return unless $effect_j{lcrDelay};
	my $n = shift;
	my $id = cop_add({
				chain => $n, 
				type => 'el:lcrDelay',
				cop_id => $ti{$n}->latency, # may be undef
				values => [ 0,0,0,50,0,0,0,0,0,50,1 ],
				# We will be adjusting the 
				# the third parameter, center delay (index  2)
				});
	
	$ti{$n}->set(latency => $id);  # save the id for next time
	$id;
}

## chain setup generation

# return file output entries, including Mixdown 
sub really_recording { 
	map{ /-o:(.+?\.wav)$/} grep{ /-o:/ and /\.wav$/} split "\n", $chain_setup
}

sub generate_setup { 
	# return 1 if successful
	# catch errors from generate_setup_try() and cleanup
	$debug2 and print "&generate_setup\n";
	# save current track
	$old_this_track = $this_track;
	initialize_chain_setup_vars();
	local $@; # don't propagate errors
		# NOTE: it would be better to use try/catch
	track_memoize(); 			# freeze track state 
	eval { &generate_setup_try }; # gets @_ passed to generate_setup()
	remove_temporary_tracks();  # cleanup
	track_unmemoize(); 			# unfreeze track state
	$this_track = $old_this_track;
	if ($@){
		say("error caught while generating setup: $@");
		initialize_chain_setup_vars() unless $debug;
		return
	}
	1;
}
sub generate_setup_try {  # TODO: move operations below to buses
	$debug2 and print "&generate_setup_try\n";
	my $automix = shift; # route Master to null_out if present
	add_paths_for_main_tracks();
	$debug and say "The graph is:\n$g";
	add_paths_for_recording();
	$debug and say "The graph is:\n$g";
	add_paths_for_aux_sends();
	$debug and say "The graph is:\n$g";
	map{ $_->apply() } grep{ (ref $_) =~ /Send|Sub/ } Audio::Nama::Bus::all();
	$debug and say "The graph is:\n$g";
	add_paths_from_Master(); # do they affect automix?
	$debug and say "The graph is:\n$g";

	# re-route Master to null for automix
	if( $automix){
		$g->delete_edges(map{@$_} $g->edges_from('Master')); 
		$g->add_edge(qw[Master null_out]);
		$debug and say "The graph is:\n$g";
	}
	add_paths_for_mixdown_handling();
	$debug and say "The graph is:\n$g";
	prune_graph();
	$debug and say "The graph is:\n$g";

	Audio::Nama::Graph::expand_graph($g); 

	$debug and say "The expanded graph is:\n$g";

	# insert handling
	Audio::Nama::Graph::add_inserts($g);

	$debug and say "The expanded graph with inserts is\n$g";

	# create IO lists %inputs and %outputs

	process_routing_graph() or say("No tracks to record or play."),return;

	write_chains(); 
}
sub remove_temporary_tracks {
	$debug2 and say "&remove_temporary_tracks";
	map { $_->remove  } grep{ $_->group eq 'Temp'} Audio::Nama::Track::all();
	$this_track = $old_this_track;
}
sub initialize_chain_setup_vars {

	@io = (); 			# IO object list
	$g = Graph->new(); 	
	%inputs = %outputs = %post_input = %pre_output = ();
	@input_chains = @output_chains = @post_input = @pre_output = ();
	undef $chain_setup;
	reset_aux_chain_counter();
	{no autodie; unlink setup_file()}
}
sub add_paths_for_main_tracks {
	$debug2 and say "&add_paths_for_main_tracks";
	map{ 

		# connect signal sources to tracks
		
		my @path = $_->input_path;
		#say "Main bus track input path: @path";
		$Audio::Nama::g->add_path(@path) if @path;

		# connect tracks to Master
		
		$Audio::Nama::g->add_edge($_->name, 'Master'); 

	} 	
		grep{ 1 unless $preview eq 'doodle'
			 and $_->rec_status eq 'MON' } # exclude MON tracks in doodle mode	
		grep{ $_->rec_status ne 'OFF' }    # exclude OFF tracks
		map{$tn{$_}} 	                   # convert to Track objects
		$main->tracks;                     # list of Track names

}

sub add_paths_for_recording {
	$debug2 and say "&add_paths_for_recording";
	return if $preview; # don't record during preview modes

	# we record tracks set to REC, unless rec_defeat is set 
	# or the track belongs to the 'null' group
	my @tracks = grep{ 
			(ref $_) !~ /Slave/  						# don't record slave tracks
			and not $_->group =~ /null|Mixdown|Temp/ 	# nor these groups
			and not $_->rec_defeat        				# nor rec-defeat tracks
			and $_->rec_status eq 'REC' 
	} Audio::Nama::Track::all();
	map{ 
		# create temporary track for rec_file chain
		$debug and say "rec file link for $_->name";	
		my $name = $_->name . '_rec_file';
		my $anon = Audio::Nama::SlaveTrack->new( 
			target => $_->name,
			rw => 'OFF',
			group => 'Temp',
			name => $name);

		# connect IO
		
		$g->add_path(input_node($_->source_type), $name, 'wav_out');

		# set chain_id to R3 (if original track is 3) 
		$g->set_vertex_attributes($name, { chain_id => 'R'.$_->n });

	} @tracks;
}

sub input_node { $_[0].'_in' }
sub output_node {$_[0].'_out'}
	

sub add_paths_for_aux_sends {
	$debug2 and say "&add_paths_for_aux_sends";

	map {  add_path_for_one_aux_send( $_ ) } 
	grep { (ref $_) !~ /Slave/ 
			and $_->group !~ /Mixdown|Master/
			and $_->send_type 
			and $_->rec_status ne 'OFF' } Audio::Nama::Track::all();
}
sub add_path_for_one_aux_send {
	my $track = shift;
		my @e = ($track->name, output_node($track->send_type));
		$g->add_edge(@e);
		 $g->set_edge_attributes(@e,
			  {	track => $track->name,
				# force stereo output width
				width => 2,
				chain_id => 'S'.$track->n,});
}

sub add_paths_from_Master {
	$debug2 and say "&add_paths_from_Master";

	if ($mastering_mode){
		$g->add_path(qw[Master Eq Low Boost]);
		$g->add_path(qw[Eq Mid Boost]);
		$g->add_path(qw[Eq High Boost]);
	}
	$g->add_path($mastering_mode ?  'Boost' : 'Master',
			output_node($tn{Master}->send_type)) if $main_out;
 

}
sub add_paths_for_mixdown_handling {
	$debug2 and say "&add_paths_for_mixdown_handling";

	if ($tn{Mixdown}->rec_status eq 'REC'){
		my @p = (($mastering_mode ? 'Boost' : 'Master'), ,'Mixdown', 'wav_out');
		$g->add_path(@p);
		$g->set_vertex_attributes('Mixdown', {
		  	format		=> signal_format($mix_to_disk_format,$tn{Mixdown}->width),
		  	chain_id	=> "Mixdown" },
		); 
		# no effects will be applied because effects are on chain 2
												 
	# Mixdown handling - playback
	
	} elsif ($tn{Mixdown}->rec_status eq 'MON'){
			my @e = qw(wav_in Mixdown soundcard_out);
			$g->add_path(@e);
			$g->set_vertex_attributes('Mixdown', {
				send_type	=> $tn{Master}->send_type,
				send_id		=> $tn{Master}->send_id,
				chain			=> "Mixdown" }); 
		# no effects will be applied because effects are on chain 2
	}
}
sub prune_graph {
	$debug2 and say "&prune_graph";
	# prune graph: remove tracks lacking inputs or outputs
	Audio::Nama::Graph::remove_inputless_tracks($g);
	Audio::Nama::Graph::remove_outputless_tracks($g); 
}
# new object based dispatch from routing graph
	
sub process_routing_graph {
	$debug2 and say "&process_routing_graph";
	@io = map{ dispatch($_) } $g->edges;
	$debug and map $_->dumpp, @io;
	map{ $inputs{$_->ecs_string} //= [];
		push @{$inputs{$_->ecs_string}}, $_->chain_id;
		$post_input{$_->chain_id} = $_->ecs_extra if $_->ecs_extra;
	} grep { $_->direction eq 'input' } @io;
	map{ $outputs{$_->ecs_string} //= [];
		push @{$outputs{$_->ecs_string}}, $_->chain_id;
		$pre_output{$_->chain_id} = $_->ecs_extra if $_->ecs_extra;
	} grep { $_->direction eq 'output' } @io;
	no warnings 'numeric';
	my @in_keys = values %inputs;
	my @out_keys = values %outputs;
	use warnings 'numeric';
	%is_ecasound_chain = map{ $_, 1} map{ @$_ } values %inputs;
	%inputs = reverse %inputs;	
	%outputs = reverse %outputs;	
	@input_chains = sort map {'-a:'.join(',',sort by_chain @$_)." $inputs{$_}"} @in_keys;
	@output_chains = sort map {'-a:'.join(',',sort by_chain @$_)." $outputs{$_}"} @out_keys;
	@post_input = sort by_index map{ "-a:$_ $post_input{$_}"} keys %post_input;
	@pre_output = sort by_index map{ "-a:$_ $pre_output{$_}"} keys %pre_output;
	@input_chains + @output_chains # to sense empty chain setup
}
{ my ($m,$n,$o,$p,$q,$r);
sub by_chain {
	($m,$n,$o) = $a =~ /(\D*)(\d+)(\D*)/ ;
	($p,$q,$r) = $b =~ /(\D*)(\d+)(\D*)/ ;
	if ($n != $q){ $n <=> $q }
	elsif ( $m ne $p){ $m cmp $p }
	else { $o cmp $r }
}
}
sub by_index {
	my ($i) = $a =~ /(\d+)/;
	my ($j) = $b =~ /(\d+)/;
	$i <=> $j
}

sub non_track_dispatch {

	# loop -> loop
	#	
	# assign chain_id to edge based on chain_id of left-side loop's
	# corresponding track:
	#	
	# hihat_out -- J7a -> Master_in
	#
	# soundcard_in -> wav_out (rec_file)
	#
	# currently handled using an anonymous track
	#
	# we expect edge attributes 
	# to have been provided for handling this. 

	# loop -> soundcard_out
	#
	# track7-soundcard_out as aux_send will have chain id S7
	# that will be transferred by expand_graph() to 
	# the new edge, loop-soundcard-out

	# we will issue two IO objects, one for the chain input
	# fragment, one for the chain output
	
	
	my $edge = shift;
	$debug and say "non-track dispatch: ",join ' -> ',@$edge;
	my $eattr = $g->get_edge_attributes(@$edge) // {};
	$debug and say "found edge attributes: ",yaml_out($eattr) if $eattr;

	my $vattr = $g->get_vertex_attributes($edge->[0]) // {};
	$debug and say "found vertex attributes: ",yaml_out($vattr) if $vattr;

	if ( ! $eattr->{chain_id} and ! $vattr->{chain_id} ){
		my $n = $eattr->{n} || $vattr->{n};
		$eattr->{chain_id} = jumper_count($n);
	}
	my @direction = qw(input output);
	map{ 
		my $direction = shift @direction;
		my $class = Audio::Nama::IO::get_class($_, $direction);
		my $attrib = {%$vattr, %$eattr};
		$attrib->{endpoint} //= $_ if Audio::Nama::Graph::is_a_loop($_); 
		$debug and say "non-track: $_, class: $class, chain_id: $attrib->{chain_id},",
 			"device_id: $attrib->{device_id}";
		$class->new($attrib ? %$attrib : () ) } @$edge;
		# we'd like to $class->new(override($edge->[0], $edge)) } @$edge;
}

{ 
### counter for jumper chains 
#
#   sequence: J1 J1a J1b J1c, J2, J3, J4, J4d, J4e

my %used;
my $counter;
my $prefix = 'J';
reset_aux_chain_counter();
  
sub reset_aux_chain_counter {
	%used = ();
	$counter = 'a';
}
sub jumper_count {
	my $track_index = shift;
	my $try1 = $prefix . $track_index;
	$used{$try1}++, return $try1 unless $used{$try1};
	$try1 . $counter++;
}
}
	

sub dispatch { # creates an IO object from a graph edge
my $edge = shift;
	return non_track_dispatch($edge) if not grep{ $tn{$_} } @$edge ;
	$debug and say 'dispatch: ',join ' -> ',  @$edge;
	my($name, $endpoint, $direction) = decode_edge($edge);
	$debug and say "name: $name, endpoint: $endpoint, direction: $direction";
	my $track = $tn{$name};
	my $class = Audio::Nama::IO::get_class( $endpoint, $direction );
		# we need the $direction because there can be 
		# edges to and from loop,Master_in
	my @args = (track => $name,
			endpoint => $endpoint, # for loops
				chain_id => $tn{$name}->n, # default
				override($name, $edge));   # priority: edge > node
	#say "dispatch class: $class";
	$class->new(@args);
}
sub decode_edge {
	# assume track-endpoint or endpoint-track
	# return track, endpoint
	my ($a, $b) = @{$_[0]};
	#say "a: $a, b: $b";
	my ($name, $endpoint) = $tn{$a} ? @{$_[0]} : reverse @{$_[0]} ;
	my $direction = $tn{$a} ? 'output' : 'input';
	($name, $endpoint, $direction)
}
sub override {
	# data from edges has priority over data from vertexes
	# we specify $name, because it could be left or right 
	# vertex
	$debug2 and say "&override";
	my ($name, $edge) = @_;
	(override_from_vertex($name), override_from_edge($edge))
}
	
sub override_from_vertex {
	my $name = shift;
		warn("undefined graph\n"), return () unless (ref $g) =~ /Graph/;
		my $attr = $g->get_vertex_attributes($name);
		$attr ? %$attr : ();
}
sub override_from_edge {
	my $edge = shift;
		warn("undefined graph\n"), return () unless (ref $g) =~ /Graph/;
		my $attr = $g->get_edge_attributes(@$edge);
		$attr ? %$attr : ();
}
							
sub write_chains {

	$debug2 and print "&write_chains\n";

	## write general options
	
	my $globals = $ecasound_globals_default;

	# use realtime globals if they exist and we are
	# recording to a non-mixdown file
	
	$globals = $ecasound_globals_realtime
		if $ecasound_globals_realtime 
			and grep{ ! /Mixdown/} really_recording();
			# we assume there exists latency-sensitive monitor output 
			# when recording
			
	my $ecs_file = join "\n\n", 
					"# ecasound chainsetup file",
					"# general",
					$globals, 
					"# audio inputs",
					join("\n", @input_chains), "";
	$ecs_file .= join "\n\n", 
					"# post-input processing",
					join("\n", @post_input), "" if @post_input;				
	$ecs_file .= join "\n\n", 
					"# pre-output processing",
					join("\n", @pre_output), "" if @pre_output;
	$ecs_file .= join "\n\n", 
					"# audio outputs",
					join("\n", @output_chains), "";
	$debug and print "ECS:\n",$ecs_file;
	open my $setup, ">", setup_file();
	print $setup $ecs_file;
	close $setup;
	$chain_setup = $ecs_file;

}

sub signal_format {
	my ($template, $channel_count) = @_;
	$template =~ s/N/$channel_count/;
	my $format = $template;
}

## transport functions
sub load_ecs {
		my $setup = setup_file();
		#say "setup file: $setup " . ( -e $setup ? "exists" : "");
		return unless -e $setup;
		#say "passed conditional";
		eval_iam("cs-disconnect") if eval_iam("cs-connected");
		eval_iam("cs-remove") if eval_iam("cs-selected");
		eval_iam("cs-load $setup");
		eval_iam("cs-select $setup"); # needed by Audio::Ecasound, but not Net-ECI !!
		$debug and map{eval_iam($_)} qw(cs es fs st ctrl-status);
		1;
}

sub arm {

	# now that we have reconfigure_engine(), use is limited to 
	# - exiting preview
	# - automix	
	
	$debug2 and print "&arm\n";
	exit_preview_mode();
	#adjust_latency();
	generate_setup() and connect_transport();
}
sub set_preview_mode {

	# set preview mode, releasing doodle mode if necessary
	
	$debug2 and print "&preview\n";

	# do nothing if already in 'preview' mode
	
	if ( $preview eq 'preview' ){ return }

	# make an announcement if we were in rec-enabled mode

	$main->set(rw => $old_group_rw) if $old_group_rw;

	$preview = "preview";

	print "Setting preview mode.\n";
	print "Using both REC and MON inputs.\n";
	print "WAV recording is DISABLED.\n\n";
	print "Type 'arm' to enable recording.\n\n";
	# reconfigure_engine() will generate setup and start transport
}
sub set_doodle_mode {

	$debug2 and print "&doodle\n";
	return if engine_running() and really_recording();
	$preview = "doodle";

	# save rw setting of user tracks (not including null group)
	# and set those tracks to REC
	
	$old_group_rw = $main->rw;
	$main->set(rw => 'REC');
	$tn{Mixdown}->set(rw => 'OFF');
	
	# reconfigure_engine will generate setup and start transport
	
	print "Setting doodle mode.\n";
	print "Using live inputs only, with no duplicate inputs\n";
	print "Exit using 'preview' or 'arm' commands.\n";
}
sub reconfigure_engine {
	$debug2 and print "&reconfigure_engine\n";
	# skip if command line option is set
	return if $opts{R};

	return if $disable_auto_reconfigure;

	# we don't want to disturb recording/mixing
	return 1 if really_recording() and engine_running();
		# why the return value? TODO delete it

	rememoize(); # check if someone has snuck in some files
	
	find_duplicate_inputs(); # we will warn the user later

	# only act if change in configuration

	my $current = yaml_out(status_snapshot());
	my $old = yaml_out($old_snapshot);

	if ( $current eq $old and ! $regenerate_setup){
			$debug and print ("no change in setup\n");
			return;
	}
	$debug and print ("setup change\n");

# 	# restore playback position unless 
# 	
# 	#  - doodle mode
# 	#  - change in global version
#     #  - change in project
#     #  - user or Mixdown track is REC enabled
# 	
# 	my $old_pos;
# 
# 	my $will_record = ! $preview 
# 						&&  grep { $_->{rec_status} eq 'REC' } 
# 							@{ $status_snapshot->{tracks} };
# 
# 	# restore playback position if possible
# 
# 	if (	$preview eq 'doodle'
# 		 	or  $old_snapshot->{project} ne $status_snapshot->{project} 
# 			or  $old_snapshot->{global_version} 
# 					ne $status_snapshot->{global_version} 
# 			or  $will_record  ){
# 
# 		$old_pos = undef;
# 
# 	} else { $old_pos = eval_iam('getpos') }
# 
# 	my $was_running = engine_running();
# 	stop_transport() if $was_running;

	$old_snapshot = status_snapshot();

	print STDOUT Audio::Nama::Text::show_tracks(Audio::Nama::Track::all()) ;
	if ( generate_setup() ){
		#say "I generated a new setup";
		print STDOUT Audio::Nama::Text::show_tracks_extra_info();
		connect_transport();
# 		eval_iam("setpos $old_pos") if $old_pos; # temp disable
# 		start_transport() if $was_running and ! $will_record;
		$ui->flash_ready;
	}
}
sub setup_file { join_path( project_dir(), $chain_setup_file) };

		
sub exit_preview_mode { # exit preview and doodle modes

		$debug2 and print "&exit_preview_mode\n";
		return unless $preview;
		stop_transport() if engine_running();
		$debug and print "Exiting preview/doodle mode\n";
		$preview = 0;
		$main->set(rw => $old_group_rw) if $old_group_rw;

}

sub find_duplicate_inputs { # in Main bus only

	%duplicate_inputs = ();
	%already_used = ();
	$debug2 and print "&find_duplicate_inputs\n";
	map{	my $source = $_->source;
			$duplicate_inputs{$_->name}++ if $already_used{$source} ;
		 	$already_used{$source} //= $_->name;
	} 
	grep { $_->rw eq 'REC' }
	map{ $tn{$_} }
	$main->tracks(); # track names;
}


sub adjust_latency {

	$debug2 and print "&adjust_latency\n";
	map { $copp{$_->latency}[0] = 0  if $_->latency() } 
		Audio::Nama::Track::all();
	set_preview_mode();
	exit_preview_mode();
	my $cop_status = eval_iam('cop-status');
	$debug and print $cop_status;
	my $chain_re  = qr/Chain "(\d+)":\s+(.*?)(?=Chain|$)/s;
	my $latency_re = qr/\[\d+\]\s+latency\s+([\d\.]+)/;
	my %chains = $cop_status =~ /$chain_re/sg;
	$debug and print yaml_out(\%chains);
	my %latency;
	map { my @latencies = $chains{$_} =~ /$latency_re/g;
			$debug and print "chain $_: latencies @latencies\n";
			my $chain = $_;
		  map{ $latency{$chain} += $_ } @latencies;
		 } grep { $_ > 2 } sort keys %chains;
	$debug and print yaml_out(\%latency);
	my $max;
	map { $max = $_ if $_ > $max  } values %latency;
	$debug and print "max: $max\n";
	map { my $adjustment = ($max - $latency{$_}) /
			$cfg{abbreviations}{frequency} * 1000;
			$debug and print "chain: $_, adjustment: $adjustment\n";
			effect_update_copp_set($ti{$_}->latency, 2, $adjustment);
			} keys %latency;
}

sub connect_transport {
	$debug2 and print "&connect_transport\n";
	my $no_transport_status = shift;
	load_ecs() or say("No chain setup, engine not ready."), return;
	eval_iam("cs-selected") and	eval_iam("cs-is-valid")
		or say("Invalid chain setup, engine not ready."),return;
	find_op_offsets(); 
	eval_iam('cs-connect');
	apply_ops();
	# or say("Failed to connect setup, engine not ready"),return;
	my $status = eval_iam("engine-status");
	if ($status ne 'not started'){
		print("Invalid chain setup, cannot connect engine.\n");
		return;
	}
	eval_iam('engine-launch');
	$status = eval_iam("engine-status");
	if ($status ne 'stopped'){
		print "Failed to launch engine. Engine status: $status\n";
		return;
	}
	$length = eval_iam('cs-get-length'); 
	$ui->length_display(-text => colonize($length));
	# eval_iam("cs-set-length $length") unless @record;
	$ui->clock_config(-text => colonize(0));
	disconnect_jack_ports();
	connect_jack_ports();
	transport_status() unless $no_transport_status;
	$ui->flash_ready();
	#print eval_iam("fs");
	1;
	
}

sub connect_jack_ports {

	# use a heuristic to map port names to track channels
		
	# If track is mono, all to one input
	# If track is stereo, map as follows:
	# 
	# L or l: 1
	# R or r: 2
	# 
	# # if first entry ends with zero we use this mapping
	# 0: 1 
	# 1: 2
	# 
	# # otherwise we use this mapping
	# 1: 1
	# 2: 2
	# 
	# If track is more than stereo, use linenumber % channel_count
	# 
	# 1st: 1
	# 2nd: 2
	# 3rd: 3
	# ...

	my $dis = shift;
	my $offset;
	my %map_RL = (L => 1, R => 2);
	map{  my $track = $_; 
 		  my $name = $track->name;
 		  my $dest = "ecasound:$name\_in_";
 		  my $file = join_path(project_root(), $track->name.'.ports');
		  my $line_number = 0;
		  if( $track->rec_status eq 'REC' and -e $file){ 
			for (io($file)->slurp){   
					# $_ is the source port name
					chomp;
					# skip silently if port doesn't exist
					return unless $jack{$_};	
		  			my $cmd = q(jack_).$dis.qq(connect "$_" $dest);
					# define offset once based on first port line
					# ends in zero: 1 
					# ends in one:  0
					/(\d)$/ and $offset //= ! $1;
					#$debug and say "offset: $offset";
					if( $track->width == 1){ $cmd .= "1" }
					elsif( $track->width == 2){
						my($suffix) = /([LlRr]|\d+)$/;
						#say "suffix: $suffix";
						$cmd .= ($suffix =~ /\d/) 
							? ($suffix + $offset)
							: $map_RL{uc $suffix};
					} else { $cmd .= ($line_number % $track->width + 1) }
					$line_number++;
					$debug and say $cmd;
					system $cmd;
			} ;
		  }
 	 } grep{ $_->source_type eq 'jack_port' and $_->rec_status eq 'REC' 
	 } Audio::Nama::Track::all();
}

sub disconnect_jack_ports { connect_jack_ports('dis') }

sub transport_status {
	
	map{ 
		say("Warning: $_: input ",$tn{$_}->source,
		" is already used by track ",$already_used{$tn{$_}->source},".")
		if $duplicate_inputs{$_};
	} grep { $tn{$_}->rec_status eq 'REC' } $main->tracks;


	# assume transport is stopped
	# print looping status, setup length, current position
	my $start  = Audio::Nama::Mark::loop_start();
	my $end    = Audio::Nama::Mark::loop_end();
	#print "start: $start, end: $end, loop_enable: $loop_enable\n";
	if (%cooked_record_pending){
		say join(" ", keys %cooked_record_pending), ": ready for caching";
	}
	if ($loop_enable and $start and $end){
		#if (! $end){  $end = $start; $start = 0}
		print "looping from ", d1($start), 
			($start > 120 
				? " (" . colonize( $start ) . ") "  
				: " " ),
						"to ", d1($end),
			($end > 120 
				? " (".colonize( $end ). ") " 
				: " " ),
				$/;
	}
	say "Engine is ready.";
	print "setup length is ", d1($length), 
		($length > 120	?  " (" . colonize($length). ")" : "" )
		,$/;
	print "now at ", colonize( eval_iam( "getpos" )), $/;
	print "\nPress SPACE to start or stop engine.\n\n"
		if $press_space_to_start_transport;
	#$term->stuff_char(10); 
}
sub start_transport { 

	# set up looping event if needed
	# mute unless recording
	# start
	# wait 0.5s
	# unmute
	# start heartbeat
	# report engine status
	# sleep 1s

	$debug2 and print "&start_transport\n";
	carp("Invalid chain setup, aborting start.\n"),return unless eval_iam("cs-is-valid");

	print "\nstarting at ", colonize(int eval_iam("getpos")), $/;
	schedule_wraparound();
	mute();
	eval_iam('start');
	sleeper(0.5) unless really_recording();
	unmute();
	$ui->set_engine_mode_color_display();
	start_heartbeat();
	sleeper(0.5);
	print "engine is ", eval_iam("engine-status"), "\n\n"; 
	sleeper(0.5);
	
}
sub stop_transport { 

	$debug2 and print "&stop_transport\n"; 
	mute();
	eval_iam('stop');	
	sleeper(0.5);
	print "\nengine is ", eval_iam("engine-status"), "\n\n"; 
	unmute();
	stop_heartbeat();
	$ui->project_label_configure(-background => $old_bg);
}
sub transport_running { eval_iam('engine-status') eq 'running'  }

sub disconnect_transport {
	return if transport_running();
		eval_iam("cs-disconnect") if eval_iam("cs-connected");
}

sub start_heartbeat {
 	$event_id{heartbeat} = AE::timer(0, 1, \&Audio::Nama::heartbeat);
}

sub stop_heartbeat {
	$event_id{heartbeat} = undef; 
	$ui->reset_engine_mode_color_display();
	rec_cleanup() }

sub heartbeat {

	#	print "heartbeat fired\n";

	my $here   = eval_iam("getpos");
	my $status = eval_iam('engine-status');
	say("\nengine is stopped"),revise_prompt(),stop_heartbeat()
		#if $status =~ /finished|error|stopped/;
		if $status =~ /finished|error/;
	#print join " ", $status, colonize($here), $/;
	my ($start, $end);
	$start  = Audio::Nama::Mark::loop_start();
	$end    = Audio::Nama::Mark::loop_end();
	schedule_wraparound() 
		if $loop_enable 
		and defined $start 
		and defined $end 
		and ! really_recording();

	update_clock_display();

}

sub update_clock_display { 
	$ui->clock_config(-text => colonize(eval_iam('cs-get-position')));
}
sub schedule_wraparound {

	return unless $loop_enable;
	my $here   = eval_iam("getpos");
	my $start  = Audio::Nama::Mark::loop_start();
	my $end    = Audio::Nama::Mark::loop_end();
	my $diff = $end - $here;
	$debug and print "here: $here, start: $start, end: $end, diff: $diff\n";
	if ( $diff < 0 ){ # go at once
		eval_iam("setpos ".$start);
		cancel_wraparound();
	} elsif ( $diff < 3 ) { #schedule the move
	$ui->wraparound($diff, $start);
		
		;
	}
}
sub cancel_wraparound {
	$event_id{wraparound} = undef;
}
sub wraparound {
	package Audio::Nama;
	@_ = discard_object(@_);
	my ($diff, $start) = @_;
	#print "diff: $diff, start: $start\n";
	$event_id{wraparound} = undef;
	$event_id{wraparound} = AE::timer($diff,0, sub{set_position($start)});
}
sub poll_jack { $event_id{poll_jack} = AE::timer(0,5,\&jack_update) }


sub mute {
	return if $tn{Master}->rw eq 'OFF' or really_recording();
	$tn{Master}->mute;
}
sub unmute {
	return if $tn{Master}->rw eq 'OFF' or really_recording();
	$tn{Master}->unmute;
}

# for GUI transport controls

sub toggle_unit {
	if ($unit == 1){
		$unit = 60;
		
	} else{ $unit = 1; }
}
sub show_unit { $time_step->configure(
	-text => ($unit == 1 ? 'Sec' : 'Min') 
)}

# Mark routines

sub drop_mark {
	$debug2 and print "drop_mark()\n";
	my $name = shift;
	my $here = eval_iam("cs-get-position");

	print("mark exists already\n"), return 
		if grep { $_->time == $here } Audio::Nama::Mark::all();

	my $mark = Audio::Nama::Mark->new( time => $here, 
							name => $name);

		$ui->marker($mark); # for GUI
}
sub mark {
	$debug2 and print "mark()\n";
	my $mark = shift;
	my $pos = $mark->time;
	if ($markers_armed){ 
			$ui->destroy_marker($pos);
			$mark->remove;
		    arm_mark_toggle(); # disarm
	}
	else{ 

		set_position($pos);
	}
}

sub next_mark {
	my $jumps = shift;
	$jumps and $jumps--;
	my $here = eval_iam("cs-get-position");
	my @marks = sort { $a->time <=> $b->time } @Audio::Nama::Mark::all;
	for my $i ( 0..$#marks ){
		if ($marks[$i]->time - $here > 0.001 ){
			$debug and print "here: $here, future time: ",
			$marks[$i]->time, $/;
			eval_iam("setpos " .  $marks[$i+$jumps]->time);
			$this_mark = $marks[$i];
			return;
		}
	}
}
sub previous_mark {
	my $jumps = shift;
	$jumps and $jumps--;
	my $here = eval_iam("cs-get-position");
	my @marks = sort { $a->time <=> $b->time } @Audio::Nama::Mark::all;
	for my $i ( reverse 0..$#marks ){
		if ($marks[$i]->time < $here ){
			eval_iam("setpos " .  $marks[$i+$jumps]->time);
			$this_mark = $marks[$i];
			return;
		}
	}
}
	

## jump recording head position

sub to_start { 
	return if really_recording();
	set_position( 0 );
}
sub to_end { 
	# ten seconds shy of end
	return if really_recording();
	my $end = eval_iam('cs-get-length') - 10 ;  
	set_position( $end);
} 
sub jump {
	return if really_recording();
	my $delta = shift;
	$debug2 and print "&jump\n";
	my $here = eval_iam('getpos');
	$debug and print "delta: $delta\nhere: $here\nunit: $unit\n\n";
	my $new_pos = $here + $delta * $unit;
	$new_pos = $new_pos < $length ? $new_pos : $length - 10;
	set_position( $new_pos );
	sleeper( 0.6);
}
## post-recording functions
sub rec_cleanup {  
	$debug2 and print "&rec_cleanup\n";
	$debug && print("transport still running, can't cleanup"),return if transport_running();
	if( my (@files) = new_files_were_recorded() ){
		say join $/, "Now reviewing your recorded files...", (@files);
		(grep /Mixdown/, @files) ? command_process('mixplay') : post_rec_configure();
	reconfigure_engine();
	}
}
sub post_rec_configure {

		$ui->global_version_buttons(); # recreate
		map{ $_->set(rw => 'MON')} Audio::Nama::Bus::all();
		$ui->refresh();
		reconfigure_engine();
}
sub new_files_were_recorded {
 	return unless my @files = really_recording();
	$debug and print join $/, "intended recordings:", @files;
	my @recorded =
		grep { 	my ($name, $version) = /([^\/]+)_(\d+).wav$/;
				if (-e ) {
					if (-s  > 44100) { # 0.5s x 16 bits x 44100/s
						$debug and print "found bigger than 44100 bytes:\n";
						$debug and print "$_\n";
						$tn{$name}->set(active => undef) if $tn{$name};
						$ui->update_version_button($tn{$name}->n, $version);
					1;
					}
					else { unlink $_; 0 }
				}
		} @files;
	if(@recorded){
		rememoize();
		say join $/,"recorded:",@recorded;
	}
	@recorded 
} 

## effect functions

sub add_effect {
	
	$debug2 and print "&add_effect\n";
	
	my %p 			= %{shift()};
	my ($n,$code,$parent_id,$id,$parameter,$values) =
		@p{qw( chain type parent_id cop_id parameter values)};
	my $i = $effect_i{$code};

	return if $id and ($id eq $ti{$n}->vol 
				or $id eq $ti{$n}->pan);   # skip these effects 
			   								# already created in add_track

	$id = cop_add(\%p); 
	%p = ( %p, cop_id => $id); # replace chainop id
	$ui->add_effect_gui(\%p) unless $ti{$n}->hide;
	if( eval_iam('cs-selected') and eval_iam('cs-is-valid') ){
		my $er = engine_running();
		$ti{$n}->mute if $er;
		apply_op($id);
		$ti{$n}->unmute if $er;
	}
	$id;

}
sub modify_effect {
	my ($op_id, $parameter, $sign, $value) = @_;
	print("$op_id: effect does not exist\n"), return 
		unless $cops{$op_id};

		my $new_value = $value; 
		if ($sign) {
			$new_value = 
 			eval (join " ",
 				$copp{$op_id}->[$parameter], 
 				$sign,
 				$value);
		}
	$debug and print "id $op_id p: $parameter, sign: $sign value: $value\n";
	effect_update_copp_set( 
		$op_id, 
		$parameter, 
		$new_value);
}

sub remove_effect { 
	@_ = discard_object(@_);
	$debug2 and print "&remove_effect\n";
	my $id = shift;
	carp("$id: does not exist, skipping...\n"), return unless $cops{$id};
	my $n = $cops{$id}->{chain};
		
	my $parent = $cops{$id}->{belongs_to} ;
	$debug and print "id: $id, parent: $parent\n";

	my $object = $parent ? q(controller) : q(chain operator); 
	$debug and print qq(ready to remove $object "$id" from track "$n"\n);

	$ui->remove_effect_gui($id);

		# recursively remove children
		$debug and print "children found: ", join "|",@{$cops{$id}->{owns}},"\n";
		map{remove_effect($_)}@{ $cops{$id}->{owns} } 
			if defined $cops{$id}->{owns};
;

	if ( ! $parent ) { # i am a chain operator, have no parent
		remove_op($id);

	} else {  # i am a controller

	# remove the controller
 			
 		remove_op($id);

	# i remove ownership of deleted controller

		$debug and print "parent $parent owns list: ", join " ",
			@{ $cops{$parent}->{owns} }, "\n";

		@{ $cops{$parent}->{owns} }  =  grep{ $_ ne $id}
			@{ $cops{$parent}->{owns} } ; 
		$cops{$id}->{belongs_to} = undef;
		$debug and print "parent $parent new owns list: ", join " ",
			@{ $cops{$parent}->{owns} } ,$/;

	}
	# remove id from track object

	$ti{$n}->remove_effect( $id ); 
	delete $cops{$id}; # remove entry from chain operator list
	delete $copp{$id}; # remove entry from chain operator parameters list
}


sub nama_effect_index { # returns nama chain operator index
						# does not distinguish op/ctrl
	my $id = shift;
	my $n = $cops{$id}->{chain};
	$debug and print "id: $id n: $n \n";
	$debug and print join $/,@{ $ti{$n}->ops }, $/;
		for my $pos ( 0.. scalar @{ $ti{$n}->ops } - 1  ) {
			return $pos if $ti{$n}->ops->[$pos] eq $id; 
		};
}
sub ecasound_effect_index { 
	my $id = shift;
	my $n = $cops{$id}->{chain};
	my $opcount;  # one-based
	$debug and print "id: $id n: $n \n",join $/,@{ $ti{$n}->ops }, $/;
	for my $op (@{ $ti{$n}->ops }) { 
			# increment only for ops, not controllers
			next if $cops{$op}->{belongs_to};
			++$opcount;
			last if $op eq $id
	} 
	$offset{$n} + $opcount;
}



sub remove_op {

	$debug2 and print "&remove_op\n";
	return unless eval_iam('cs-connected') and eval_iam('cs-is-valid');
	my $id = shift;
	my $n = $cops{$id}->{chain};
	my $index;
	my $parent = $cops{$id}->{belongs_to}; 

	# select chain
	
	return unless ecasound_select_chain($n);

	# deal separately with controllers and chain operators

	if ( !  $parent ){ # chain operator
		$debug and print "no parent, assuming chain operator\n";
	
		$index = ecasound_effect_index( $id );
		$debug and print "ops list for chain $n: @{$ti{$n}->ops}\n";
		$debug and print "operator id to remove: $id\n";
		$debug and print "ready to remove from chain $n, operator id $id, index $index\n";
		$debug and eval_iam("cs");
		eval_iam("cop-select ". ecasound_effect_index($id) );
		$debug and print "selected operator: ", eval_iam("cop-selected"), $/;
		eval_iam("cop-remove");
		$debug and eval_iam("cs");

	} else { # controller

		$debug and print "has parent, assuming controller\n";

		my $ctrl_index = ctrl_index($id);
		$debug and print eval_iam("cs");
		eval_iam("cop-select ".  ecasound_effect_index(root_parent($id)));
		$debug and print "selected operator: ", eval_iam("cop-selected"), $/;
		eval_iam("ctrl-select $ctrl_index");
		eval_iam("ctrl-remove");
		$debug and print eval_iam("cs");
	}
}


# Track sax effects: A B C GG HH II D E F
# GG HH and II are controllers applied to chain operator C
# 
# to remove controller HH:
#
# for Ecasound, chain op index = 3, 
#               ctrl index     = 2
#                              = nama_effect_index HH - nama_effect_index C 
#               
#
# for Nama, chain op array index 2, 
#           ctrl arrray index = chain op array index + ctrl_index
#                             = effect index - 1 + ctrl_index 
#
#

sub root_parent { 
	my $id = shift;
	my $parent = $cops{$id}->{belongs_to};
	carp("$id: has no parent, skipping...\n"),return unless $parent;
	my $root_parent = $cops{$parent}->{belongs_to};
	$parent = $root_parent || $parent;
	$debug and print "$id: is a controller-controller, root parent: $parent\n";
	$parent;
}

sub ctrl_index { 
	my $id = shift;
	nama_effect_index($id) - nama_effect_index(root_parent($id));

}
sub cop_add {
	$debug2 and print "&cop_add\n";
	my $p = shift;
	my %p = %$p;
	$debug and say yaml_out($p);

	# return an existing id 
	return $p{cop_id} if $p{cop_id};
	

	# use an externally provided (magical) id or the
	# incrementing counter
	
	my $id = $magical_cop_id || $cop_id;

	# make entry in %cops with chain, code, display-type, children

	my ($n, $type, $parent_id, $parameter)  = 
		@p{qw(chain type parent_id parameter)};
	my $i = $effect_i{$type};


	$debug and print "Issuing a cop_id for track $n: $id\n";

	$cops{$id} = {chain => $n, 
					  type => $type,
					  display => $effects[$i]->{display},
					  owns => [] }; 

	$p->{cop_id} = $id;

	# set defaults
	
	if (! $p{values}){
		my @vals;
		$debug and print "no settings found, loading defaults if present\n";
		my $i = $effect_i{ $cops{$id}->{type} };
		
		# don't initialize first parameter if operator has a parent
		# i.e. if operator is a controller
		
		for my $p ($parent_id ? 1 : 0..$effects[$i]->{count} - 1) {
		
			my $default = $effects[$i]->{params}->[$p]->{default};
			push @vals, $default;
		}
		$debug and print "copid: $id defaults: @vals \n";
		$copp{$id} = \@vals;
	}

	if ($parent_id) {
		$debug and print "parent found: $parent_id\n";

		# store relationship
		$debug and print "parent owns" , join " ",@{ $cops{$parent_id}->{owns}}, "\n";

		push @{ $cops{$parent_id}->{owns}}, $id;
		$debug and print join " ", "my attributes:", (keys %{ $cops{$id} }), "\n";
		$cops{$id}->{belongs_to} = $parent_id;
		$debug and print join " ", "my attributes again:", (keys %{ $cops{$id} }), "\n";
		$debug and print "parameter: $parameter\n";

		# set fx-param to the parameter number, which one
		# above the zero-based array offset that $parameter represents
		
		$copp{$id}->[0] = $parameter + 1; 
		
 		# find position of parent and insert child immediately afterwards

 		my $end = scalar @{ $ti{$n}->ops } - 1 ; 
 		for my $i (0..$end){
 			splice ( @{$ti{$n}->ops}, $i+1, 0, $id ), last
 				if $ti{$n}->ops->[$i] eq $parent_id
 		}
	}
	else { push @{$ti{$n}->ops }, $id; } 

	# set values if present
	
	# ugly! The passed values ref may be used for multiple
	# instances, so we copy it here [ @$values ]
	
	$copp{$id} = [ @{$p{values}} ] if $p{values};

	# make sure the counter $cop_id will not occupy an
	# already used value
	
	while( $cops{$cop_id}){$cop_id++};

	$id;
}

sub effect_update_copp_set {

	my ($id, $param, $val) = @_;
	effect_update( @_ );
	$copp{$id}->[$param] = $val;
}
	

sub effect_update {

	# update the parameters of the Ecasound chain operator
	# referred to by a Nama operator_id
	
	#$debug2 and print "&effect_update\n";
	my $valid_setup = eval_iam("cs-selected") and eval_iam("cs-is-valid");
	return unless $valid_setup;
	my $es = eval_iam("engine-status");
	$debug and print "engine is $es\n";
	return if $es !~ /not started|stopped|running/;

	my ($id, $param, $val) = @_;
	$param++; # so the value at $p[0] is applied to parameter 1
	carp("$id: effect not found. skipping...\n"), return unless $cops{$id};
	my $chain = $cops{$id}{chain};
	return unless $is_ecasound_chain{$chain};

	$debug and print "chain $chain id $id param $param value $val\n";

	# $param is zero-based. 
	# %copp is  zero-based.

 	$debug and print join " ", @_, "\n";	

	my $old_chain = eval_iam('c-selected') if eval_iam('cs-selected');
	ecasound_select_chain($chain);

	# update Ecasound's copy of the parameter
	if( is_controller($id)){
		my $i = ecasound_controller_index($id);
		$debug and print 
		"controller $id: track: $chain, index: $i param: $param, value: $val\n";
		eval_iam("ctrl-select $i");
		eval_iam("ctrlp-select $param");
		eval_iam("ctrlp-set $val");
	}
	else { # is operator
		my $i = ecasound_operator_index($id);
		$debug and print 
		"operator $id: track $chain, index: $i, offset: ",
		$offset{$chain}, " param $param, value $val\n";
		eval_iam("cop-select ". ($offset{$chain} + $i));
		eval_iam("copp-select $param");
		eval_iam("copp-set $val");
	}
	ecasound_select_chain($old_chain);
}

sub sync_effect_parameters {
	# when a controller changes an effect parameter
	# the effect state can differ from the state in
	# %copp, Nama's effect parameter store
	#
	# this routine syncs them in prep for save_state()
	
	my $old_chain = eval_iam('c-selected');
	map{ sync_one_effect($_) } ops_with_controller();
	eval_iam("c-select $old_chain");
}

sub sync_one_effect {
		my $id = shift;
		my $chain = $cops{$id}{chain};
		eval_iam("c-select $chain");
		eval_iam("cop-select " . ( $offset{$chain} + ecasound_operator_index($id)));
		$copp{$id} = get_cop_params( scalar @{$copp{$id}} );
}

sub get_cop_params {
	my $count = shift;
	my @params;
	for (1..$count){
		eval_iam("copp-select $_");
		push @params, eval_iam("copp-get");
	}
	\@params
}
		
sub ops_with_controller {
	grep{ ! is_controller($_) }
	grep{ scalar @{$cops{$_}{owns}} }
	map{ @{ $_->ops } } 
	map{ $tn{$_} } 
	grep{ $tn{$_} } 
	$g->vertices;
}

sub is_controller { my $id = shift; $cops{$id}{belongs_to} }

sub ecasound_operator_index { # does not include offset
	my $id = shift;
	my $chain = $cops{$id}{chain};
	my $track = $ti{$chain};
	my @ops = @{$track->ops};
	my $controller_count = 0;
	my $position;
	for my $i (0..scalar @ops - 1) {
		$position = $i, last if $ops[$i] eq $id;
		$controller_count++ if $cops{$ops[$i]}{belongs_to};
	}
	$position -= $controller_count; # skip controllers 
	++$position; # translates 0th to chain-position 1
}
	
	
sub ecasound_controller_index {
	my $id = shift;
	my $chain = $cops{$id}{chain};
	my $track = $ti{$chain};
	my @ops = @{$track->ops};
	my $operator_count = 0;
	my $position;
	for my $i (0..scalar @ops - 1) {
		$position = $i, last if $ops[$i] eq $id;
		$operator_count++ if ! $cops{$ops[$i]}{belongs_to};
	}
	$position -= $operator_count; # skip operators
	++$position; # translates 0th to chain-position 1
}
	
sub fade {
	my ($id, $param, $from, $to, $seconds) = @_;

	# no fade without Timer::HiRes
	# no fade unless engine is running
	if ( ! engine_running() or ! $hires ){
		effect_update_copp_set ( $id, $param, $to );
		return;
	}

	my $steps = $seconds * $fade_resolution;
	my $wink  = 1/$fade_resolution;
	my $size = ($to - $from)/$steps;
	$debug and print "id: $id, param: $param, from: $from, to: $to, seconds: $seconds\n";
	for (1..$steps - 1){
		modify_effect( $id, $param, '+', $size);
		sleeper( $wink );
	}		
	effect_update_copp_set( 
		$id, 
		$param, 
		$to);
	
}

sub fadein {
	my ($id, $to) = @_;
	my $from  = $fade_out_level{$cops{$id}->{type}};
	fade( $id, 0, $from, $to, $fade_time);
}
sub fadeout {
	my $id    = shift;
	my $from  =	$copp{$id}[0];
	my $to	  = $fade_out_level{$cops{$id}->{type}};
	fade( $id, 0, $from, $to, $fade_time );
}

sub find_op_offsets {

	$debug2 and print "&find_op_offsets\n";
	my @op_offsets = grep{ /"\d+"/} split "\n",eval_iam("cs");
	$debug and print join "\n\n",@op_offsets; 
	for my $output (@op_offsets){
		my $chain_id;
		($chain_id) = $output =~ m/Chain "(\w*\d+)"/;
		# print "chain_id: $chain_id\n";
		next if $chain_id =~ m/\D/; # skip id's containing non-digits
									# i.e. M1
		my $quotes = $output =~ tr/"//;
		$debug and print "offset: $quotes in $output\n"; 
		$offset{$chain_id} = $quotes/2 - 1;  
	}
}
sub apply_ops {  # in addition to operators in .ecs file
	
	$debug2 and print "&apply_ops\n";
	for my $n ( map{ $_->n } Audio::Nama::Track::all() ) {
	$debug and print "chain: $n, offset: ", $offset{$n}, "\n";
 		next unless $is_ecasound_chain{$n};
		#next if $n == 2; # no volume control for mix track
		#next if ! defined $offset{$n}; # for MIX
 		#next if ! $offset{$n} ;

	# controllers will follow ops, so safe to apply all in order
		for my $id ( @{ $ti{$n}->ops } ) {
		apply_op($id);
		}
	}
	ecasound_select_chain($this_track->n);
}
sub apply_op {
	$debug2 and print "&apply_op\n";
	
	my $id = shift;
	my $selected = shift;
	$debug and print "id: $id\n";
	my $code = $cops{$id}->{type};
	my $dad = $cops{$id}->{belongs_to};
	$debug and print "chain: $cops{$id}->{chain} type: $cops{$id}->{type}, code: $code\n";
	#  if code contains colon, then follow with comma (preset, LADSPA)
	#  if code contains no colon, then follow with colon (ecasound,  ctrl)
	
	$code = '-' . $code . ($code =~ /:/ ? q(,) : q(:) );
	my @vals = @{ $copp{$id} };
	$debug and print "values: @vals\n";

	# we start to build iam command

	my $add = $dad ? "ctrl-add " : "cop-add "; 
	
	$add .= $code . join ",", @vals;

	# if my parent has a parent then we need to append the -kx  operator

	$add .= " -kx" if $cops{$dad}->{belongs_to};
	$debug and print "command:  ", $add, "\n";

	eval_iam("c-select $cops{$id}->{chain}") 
		if $selected != $cops{$id}->{chain};

	if ( $dad ) {
	eval_iam("cop-select " . ecasound_effect_index($dad));
	}

	eval_iam($add);
	$debug and print "children found: ", join ",", "|",@{$cops{$id}->{owns}},"|\n";
	my $ref = ref $cops{$id}->{owns} ;
	$ref =~ /ARRAY/ or croak "expected array";
	my @owns = @{ $cops{$id}->{owns} };
	$debug and print "owns: @owns\n";  
	#map{apply_op($_)} @owns;

}

sub prepare_effects_help {

	# presets
	map{	s/^.*? //; 				# remove initial number
					$_ .= "\n";				# add newline
					my ($id) = /(pn:\w+)/; 	# find id
					s/,/, /g;				# to help line breaks
					push @effects_help,    $_;  #store help

				}  split "\n",eval_iam("preset-register");

	# LADSPA
	my $label;
	map{ 

		if (  my ($_label) = /-(el:[-\w]+)/  ){
				$label = $_label;
				s/^\s+/ /;				 # trim spaces 
				s/'//g;     			 # remove apostrophes
				$_ .="\n";               # add newline
				push @effects_help, $_;  # store help

		} else { 
				# replace leading number with LADSPA Unique ID
				s/^\d+/$ladspa_unique_id{$label}/;

				s/\s+$/ /;  			# remove trailing spaces
				substr($effects_help[-1],0,0) = $_; # join lines
				$effects_help[-1] =~ s/,/, /g; # 
				$effects_help[-1] =~ s/,\s+$//;
				
		}

	} reverse split "\n",eval_iam("ladspa-register");


#my @lines = reverse split "\n",eval_iam("ladspa-register");
#pager( scalar @lines, $/, join $/,@lines);
	
	#my @crg = map{s/^.*? -//; $_ .= "\n" }
	#			split "\n",eval_iam("control-register");
	#pager (@lrg, @prg); exit;
}

sub prepare_static_effects_data{
	
	$debug2 and print "&prepare_static_effects_data\n";

	my $effects_cache = join_path(&project_root, $effects_cache_file);

	#print "newplugins: ", new_plugins(), $/;
	if ($opts{r} or new_plugins()){ 

		eval { unlink $effects_cache};
		print "Regenerating effects data cache\n";
	}

	if (-f $effects_cache and ! $opts{s}){  
		$debug and print "found effects cache: $effects_cache\n";
		assign_var($effects_cache, @effects_static_vars);
	} else {
		
		$debug and print "reading in effects data, please wait...\n";
		read_in_effects_data();  
		# cop-register, preset-register, ctrl-register, ladspa-register
		get_ladspa_hints();     
		integrate_ladspa_hints();
		integrate_cop_hints();
		sort_ladspa_effects();
		prepare_effects_help();
		serialize (
			file => $effects_cache, 
			vars => \@effects_static_vars,
			class => 'Audio::Nama',
			format => 'storable');
	}

	prepare_effect_index();
}

sub ladspa_plugin_list {
	my @filenames;
	for my $dir ( split ':', ladspa_path()){
		{no autodie 'opendir';
			opendir DIR, $dir or carp "failed to open directory $dir: $!\n";
		}
		push @filenames,  map{"$dir/$_"} grep{ /.so$/ } readdir DIR;
		closedir DIR;
	}
	@filenames;
}

sub new_plugins {
	my $effects_cache = join_path(&project_root, $effects_cache_file);
	my @filenames = ladspa_plugin_list();	
	push @filenames, '/usr/local/share/ecasound/effect_presets',
                 '/usr/share/ecasound/effect_presets',
                 "$ENV{HOME}/.ecasound/effect_presets";
	my $effects_cache_stamp = modified_stamp($effects_cache);
	my $latest;
	map{ my $mod = modified_stamp($_);
		 $latest = $mod if $mod > $latest } @filenames;

	$latest > $effects_cache_stamp;
}

sub modified_stamp {
	# timestamp that file was modified
	my $filename = shift;
	#print "file: $filename\n";
	my @s = stat $filename;
	$s[9];
}
sub prepare_effect_index {
	$debug2 and print "&prepare_effect_index\n";
	%effect_j = ();
	map{ 
		my $code = $_;
		my ($short) = $code =~ /:([-\w]+)/;
		if ( $short ) { 
			if ($effect_j{$short}) { warn "name collision: $_\n" }
			else { $effect_j{$short} = $code }
		}else{ $effect_j{$code} = $code };
	} keys %effect_i;
	#print yaml_out \%effect_j;
}
sub extract_effects_data {
	$debug2 and print "&extract_effects_data\n";
	my ($lower, $upper, $regex, $separator, @lines) = @_;
	carp ("incorrect number of lines ", join ' ',$upper-$lower,scalar @lines)
		if $lower + @lines - 1 != $upper;
	$debug and print"lower: $lower upper: $upper  separator: $separator\n";
	#$debug and print "lines: ". join "\n",@lines, "\n";
	$debug and print "regex: $regex\n";
	
	for (my $j = $lower; $j <= $upper; $j++) {
		my $line = shift @lines;
	
		$line =~ /$regex/ or carp("bad effect data line: $line\n"),next;
		my ($no, $name, $id, $rest) = ($1, $2, $3, $4);
		$debug and print "Number: $no Name: $name Code: $id Rest: $rest\n";
		my @p_names = split $separator,$rest; 
		map{s/'//g}@p_names; # remove leading and trailing q(') in ladspa strings
		$debug and print "Parameter names: @p_names\n";
		$effects[$j]={};
		$effects[$j]->{number} = $no;
		$effects[$j]->{code} = $id;
		$effects[$j]->{name} = $name;
		$effects[$j]->{count} = scalar @p_names;
		$effects[$j]->{params} = [];
		$effects[$j]->{display} = qq(field);
		map{ push @{$effects[$j]->{params}}, {name => $_} } @p_names
			if @p_names;
;
	}
}
sub sort_ladspa_effects {
	$debug2 and print "&sort_ladspa_effects\n";
#	print yaml_out(\%e_bound); 
	my $aa = $e_bound{ladspa}{a};
	my $zz = $e_bound{ladspa}{z};
#	print "start: $aa end $zz\n";
	map{push @ladspa_sorted, 0} ( 1 .. $aa ); # fills array slice [0..$aa-1]
	splice @ladspa_sorted, $aa, 0,
		 sort { $effects[$a]->{name} cmp $effects[$b]->{name} } ($aa .. $zz) ;
	$debug and print "sorted array length: ". scalar @ladspa_sorted, "\n";
}		
sub read_in_effects_data {
	
	$debug2 and print "&read_in_effects_data\n";

	my $lr = eval_iam("ladspa-register");

	#print $lr; 
	
	my @ladspa =  split "\n", $lr;
	
	# join the two lines of each entry
	my @lad = map { join " ", splice(@ladspa,0,2) } 1..@ladspa/2; 

	my @preset = grep {! /^\w*$/ } split "\n", eval_iam("preset-register");
	my @ctrl  = grep {! /^\w*$/ } split "\n", eval_iam("ctrl-register");
	my @cop = grep {! /^\w*$/ } split "\n", eval_iam("cop-register");

	$debug and print "found ", scalar @cop, " Ecasound chain operators\n";
	$debug and print "found ", scalar @preset, " Ecasound presets\n";
	$debug and print "found ", scalar @ctrl, " Ecasound controllers\n";
	$debug and print "found ", scalar @lad, " LADSPA effects\n";

	# index boundaries we need to make effects list and menus
	$e_bound{cop}{a}   = 1;
	$e_bound{cop}{z}   = @cop; # scalar
	$e_bound{ladspa}{a} = $e_bound{cop}{z} + 1;
	$e_bound{ladspa}{b} = $e_bound{cop}{z} + int(@lad/4);
	$e_bound{ladspa}{c} = $e_bound{cop}{z} + 2*int(@lad/4);
	$e_bound{ladspa}{d} = $e_bound{cop}{z} + 3*int(@lad/4);
	$e_bound{ladspa}{z} = $e_bound{cop}{z} + @lad;
	$e_bound{preset}{a} = $e_bound{ladspa}{z} + 1;
	$e_bound{preset}{b} = $e_bound{ladspa}{z} + int(@preset/2);
	$e_bound{preset}{z} = $e_bound{ladspa}{z} + @preset;
	$e_bound{ctrl}{a}   = $e_bound{preset}{z} + 1;
	$e_bound{ctrl}{z}   = $e_bound{preset}{z} + @ctrl;

	my $cop_re = qr/
		^(\d+) # number
		\.    # dot
		\s+   # spaces+
		(\w.+?) # name, starting with word-char,  non-greedy
		# (\w+) # name
		,\s*  # comma spaces* 
		-(\w+)    # cop_id 
		:?     # maybe colon (if parameters)
		(.*$)  # rest
	/x;

	my $preset_re = qr/
		^(\d+) # number
		\.    # dot
		\s+   # spaces+
		(\w+) # name
		,\s*  # comma spaces* 
		-(pn:\w+)    # preset_id 
		:?     # maybe colon (if parameters)
		(.*$)  # rest
	/x;

	my $ladspa_re = qr/
		^(\d+) # number
		\.    # dot
		\s+  # spaces
		(.+?) # name, starting with word-char,  non-greedy
		\s+     # spaces
		-(el:[-\w]+),? # ladspa_id maybe followed by comma
		(.*$)        # rest
	/x;

	my $ctrl_re = qr/
		^(\d+) # number
		\.     # dot
		\s+    # spaces
		(\w.+?) # name, starting with word-char,  non-greedy
		,\s*    # comma, zero or more spaces
		-(k\w+):?    # ktrl_id maybe followed by colon
		(.*$)        # rest
	/x;

	extract_effects_data(
		$e_bound{cop}{a},
		$e_bound{cop}{z},
		$cop_re,
		q(','),
		@cop,
	);


	extract_effects_data(
		$e_bound{ladspa}{a},
		$e_bound{ladspa}{z},
		$ladspa_re,
		q(','),
		@lad,
	);

	extract_effects_data(
		$e_bound{preset}{a},
		$e_bound{preset}{z},
		$preset_re,
		q(,),
		@preset,
	);
	extract_effects_data(
		$e_bound{ctrl}{a},
		$e_bound{ctrl}{z},
		$ctrl_re,
		q(,),
		@ctrl,
	);



	for my $i (0..$#effects){
		 $effect_i{ $effects[$i]->{code} } = $i; 
		 $debug and print "i: $i code: $effects[$i]->{code} display: $effects[$i]->{display}\n";
	}

	$debug and print "\@effects\n======\n", yaml_out(\@effects); ; 
}

sub integrate_cop_hints {

	my @cop_hints = @{ yaml_in( $cop_hints_yml ) };
	for my $hashref ( @cop_hints ){
		#print "cop hints ref type is: ",ref $hashref, $/;
		my $code = $hashref->{code};
		$effects[ $effect_i{ $code } ] = $hashref;
	}
}
sub ladspa_path {
	$ENV{LADSPA_PATH} || q(/usr/lib/ladspa);
}
sub get_ladspa_hints{
	$debug2 and print "&get_ladspa_hints\n";
	my @dirs =  split ':', ladspa_path();
	my $data = '';
	my %seen = ();
	my @plugins;
	for my $dir (@dirs) {
		opendir DIR, $dir or carp qq(can't open LADSPA dir "$dir" for read: $!\n);
	
		push @plugins,  
			grep{ /\.so$/ and ! $seen{$_} and ++$seen{$_}} readdir DIR;
		closedir DIR;
	};
	#pager join $/, @plugins;

	# use these regexes to snarf data
	
	my $pluginre = qr/
	Plugin\ Name:       \s+ "([^"]+)" \s+
	Plugin\ Label:      \s+ "([^"]+)" \s+
	Plugin\ Unique\ ID: \s+ (\d+)     \s+
	[^\x00]+(?=Ports) 		# swallow maximum up to Ports
	Ports: \s+ ([^\x00]+) 	# swallow all
	/x;

	my $paramre = qr/
	"([^"]+)"   #  name inside quotes
	\s+
	(.+)        # rest
	/x;
		
	my $i;

	for my $file (@plugins){
		my @stanzas = split "\n\n", qx(analyseplugin $file);
		for my $stanza (@stanzas) {

			my ($plugin_name, $plugin_label, $plugin_unique_id, $ports)
			  = $stanza =~ /$pluginre/ 
				or carp "*** couldn't match plugin stanza $stanza ***";
			$debug and print "plugin label: $plugin_label $plugin_unique_id\n";

			my @lines = grep{ /input/ and /control/ } split "\n",$ports;

			my @params;  # data
			my @names;
			for my $p (@lines) {
				next if $p =~ /^\s*$/;
				$p =~ s/\.{3}/10/ if $p =~ /amplitude|gain/i;
				$p =~ s/\.{3}/60/ if $p =~ /delay|decay/i;
				$p =~ s(\.{3})($ladspa_sample_rate/2) if $p =~ /frequency/i;
				$p =~ /$paramre/;
				my ($name, $rest) = ($1, $2);
				my ($dir, $type, $range, $default, $hint) = 
					split /\s*,\s*/ , $rest, 5;
				$debug and print join( 
				"|",$name, $dir, $type, $range, $default, $hint) , $/; 
				#  if $hint =~ /logarithmic/;
				if ( $range =~ /toggled/i ){
					$range = q(0 to 1);
					$hint .= q(toggled);
				}
				my %p;
				$p{name} = $name;
				$p{dir} = $dir;
				$p{hint} = $hint;
				my ($beg, $end, $default_val, $resolution) 
					= range($name, $range, $default, $hint, $plugin_label);
				$p{begin} = $beg;
				$p{end} = $end;
				$p{default} = $default_val;
				$p{resolution} = $resolution;
				push @params, { %p };
			}

			$plugin_label = "el:" . $plugin_label;
			$ladspa_help{$plugin_label} = $stanza;
			$effects_ladspa_file{$plugin_unique_id} = $file;
			$ladspa_unique_id{$plugin_label} = $plugin_unique_id; 
			$ladspa_unique_id{$plugin_name} = $plugin_unique_id; 
			$ladspa_label{$plugin_unique_id} = $plugin_label;
			$effects_ladspa{$plugin_label}->{name}  = $plugin_name;
			$effects_ladspa{$plugin_label}->{id}    = $plugin_unique_id;
			$effects_ladspa{$plugin_label}->{params} = [ @params ];
			$effects_ladspa{$plugin_label}->{count} = scalar @params;
			$effects_ladspa{$plugin_label}->{display} = 'scale';
		}	#	pager( join "\n======\n", @stanzas);
		#last if ++$i > 10;
	}

	$debug and print yaml_out(\%effects_ladspa); 
}

sub srate_val {
	my $input = shift;
	my $val_re = qr/(
			[+-]? 			# optional sign
			\d+				# one or more digits
			(\.\d+)?	 	# optional decimal
			(e[+-]?\d+)?  	# optional exponent
	)/ix;					# case insensitive e/E
	my ($val) = $input =~ /$val_re/; #  or carp "no value found in input: $input\n";
	$val * ( $input =~ /srate/ ? $ladspa_sample_rate : 1 )
}
	
sub range {
	my ($name, $range, $default, $hint, $plugin_label) = @_; 
	my $multiplier = 1;;
	my ($beg, $end) = split /\s+to\s+/, $range;
	$beg = 		srate_val( $beg );
	$end = 		srate_val( $end );
	$default = 	srate_val( $default );
	$default = $default || $beg;
	$debug and print "beg: $beg, end: $end, default: $default\n";
	if ( $name =~ /gain|amplitude/i ){
		$beg = 0.01 unless $beg;
		$end = 0.01 unless $end;
	}
	my $resolution = ($end - $beg) / 100;
	if    ($hint =~ /integer|toggled/i ) { $resolution = 1; }
	elsif ($hint =~ /logarithmic/ ) {

		$beg = round ( log $beg ) if $beg;
		$end = round ( log $end ) if $end;
		$resolution = ($end - $beg) / 100;
		$default = $default ? round (log $default) : $default;
	}
	
	$resolution = d2( $resolution + 0.002) if $resolution < 1  and $resolution > 0.01;
	$resolution = dn ( $resolution, 3 ) if $resolution < 0.01;
	$resolution = int ($resolution + 0.1) if $resolution > 1 ;
	
	($beg, $end, $default, $resolution)

}
sub integrate_ladspa_hints {
	$debug2 and print "&integrate_ladspa_hints\n";
	map{ 
		my $i = $effect_i{$_};
		# print ("$_ not found\n"), 
		if ($i) {
			$effects[$i]->{params} = $effects_ladspa{$_}->{params};
			# we revise the number of parameters read in from ladspa-register
			$effects[$i]->{count} = scalar @{$effects_ladspa{$_}->{params}};
			$effects[$i]->{display} = $effects_ladspa{$_}->{display};
		}
	} keys %effects_ladspa;

my %L;
my %M;

map { $L{$_}++ } keys %effects_ladspa;
map { $M{$_}++ } grep {/el:/} keys %effect_i;

for my $k (keys %L) {
	$M{$k} or $debug and print "$k not found in ecasound listing\n";
}
for my $k (keys %M) {
	$L{$k} or $debug and print "$k not found in ladspa listing\n";
}


$debug and print join "\n", sort keys %effects_ladspa;
$debug and print '-' x 60, "\n";
$debug and print join "\n", grep {/el:/} sort keys %effect_i;

#print yaml_out \@effects; exit;

}
sub d1 {
	my $n = shift;
	sprintf("%.1f", $n)
}
sub d2 {
	my $n = shift;
	sprintf("%.2f", $n)
}
sub dn {
	my ($n, $places) = @_;
	sprintf("%." . $places . "f", $n);
}
sub round {
	my $n = shift;
	return 0 if $n == 0;
	$n = int $n if $n > 10;
	$n = d2($n) if $n < 10;
	$n;
}
	

## persistent state support

sub save_state {
	$debug2 and print "&save_state\n";
	$saved_version = $VERSION;


	# some stuff get saved independently of our state file
	
	$debug and print "saving palette\n";
	$ui->save_palette;

	save_effect_chains();
	save_effect_profiles();

	# do nothing more if only Master and Mixdown
	
	if (scalar @Audio::Nama::Track::all == 2 ){
		print "No user tracks, skipping...\n";
		return;
	}

	# save stuff to state file

	my $file = shift || $state_store_file; 
	$file = join_path(&project_dir, $file) unless $file =~ m(/); 
	$file =~ /\.yml$/ or $file .= '.yml';	
	print "\nSaving state as $file\n";

	sync_effect_parameters(); # in case a controller has made a change

	# remove null keys in %cops and %copp
	
	delete $cops{''};
	delete $copp{''};

	# prepare tracks for storage
	
	$this_track_name = $this_track->name;

	@tracks_data = (); # zero based, iterate over these to restore

	$debug and print "copying tracks data\n";

	map { push @tracks_data, $_->hashref } Audio::Nama::Track::all();
	# print "found ", scalar @tracks_data, "tracks\n";

	# delete unused fields
	map { my $t = $_;
				map{ delete $t->{$_} } 
					qw(ch_r ch_m source_select send_select jack_source jack_send);
	} @tracks_data;

	$debug and print "copying bus data\n";
	@bus_data = (); # 
	map{ push @bus_data, $_->hashref } Audio::Nama::Bus::all();

	# prepare inserts data for storage
	
	$debug and print "copying inserts data\n";
	@inserts_data = ();
	while (my $k = each %Audio::Nama::Insert::by_index ){ 
		push @inserts_data, $Audio::Nama::Insert::by_index{$k}->hashref;
	}

	# prepare marks data for storage (new Mark objects)

	@marks_data = ();
	$debug and print "copying marks data\n";
	map { push @marks_data, $_->hashref } Audio::Nama::Mark::all();

	# prepare fade data for storage
	
	@fade_data = ();
	while (my $k = each %Audio::Nama::Fade::by_index ){ 
		push @fade_data, $Audio::Nama::Fade::by_index{$k}->hashref;
	}
	

	# save history

	my @history = $Audio::Nama::term->GetHistory;
	my %seen;
	@command_history = ();
	map { push @command_history, $_ 
			unless $seen{$_}; $seen{$_}++ } @history;

	$debug and print "serializing\n";
	serialize(
		file => $file, 
		format => 'yaml',
		vars => \@persistent_vars,
		class => 'Audio::Nama',
		);


	# store alsa settings

	if ( $opts{a} ) {
		my $file = $file;
		$file =~ s/\.yml$//;
		print "storing ALSA settings\n";
		print qx(alsactl -f $file.alsa store);
	}


}


sub save_effect_chains { # if they exist
	if (keys %effect_chain){
		serialize (
			file => join_path(project_root(), $effect_chain_file),
			format => 'yaml',
			vars => [ qw( %effect_chain ) ],
			class => 'Audio::Nama');
	}
}
sub save_effect_profiles { # if they exist
	if (keys %effect_profile){
		serialize (
			file => join_path(project_root(), $effect_profile_file),
			format => 'yaml',
			vars => [ qw( %effect_profile ) ],
			class => 'Audio::Nama');
	}
}
sub restore_effect_chains {

	my $file = join_path(project_root(), $effect_chain_file);
	return unless -e $file;

	# don't overwrite them if already present
	assign_var($file, qw(%effect_chain)) unless keys %effect_chain
}
sub restore_effect_profiles {

	my $file = join_path(project_root(), $effect_profile_file);
	return unless -e $file;

	# don't overwrite them if already present
	assign_var($file, qw(%effect_profile)) unless keys %effect_profile; 
}
sub assign_var {
	my ($source, @vars) = @_;
	assign_vars(
				source => $source,
				vars   => \@vars,
		#		format => 'yaml', # breaks
				class => 'Audio::Nama');
}
sub restore_state {
	$debug2 and print "&restore_state\n";
	my $file = shift;
	$file = $file || $state_store_file;
	$file = join_path(project_dir(), $file);
	$file .= ".yml" unless $file =~ /yml$/;
	! -f $file and (print "file not found: $file\n"), return;
	$debug and print "using file: $file\n";
	
	my $yaml = io($file)->all;

	# remove empty key hash lines # fixes YAML::Tiny bug
	$yaml = join $/, grep{ ! /^\s*:/ } split $/, $yaml;

	# rewrite obsolete null hash/array substitution
	$yaml =~ s/~NULL_HASH/{}/g;
	$yaml =~ s/~NULL_ARRAY/[]/g;

	# rewrite %cops 'owns' field to []
	
	$yaml =~ s/owns: ~/owns: []/g;

	# restore persistent variables

	assign_var($yaml, @persistent_vars );

	restore_effect_chains();
	restore_effect_profiles();

	##  print yaml_out \@groups_data; 
	# %cops: correct 'owns' null (from YAML) to empty array []
	
	# backward compatibility fixes for older projects

	if (! $saved_version ){

		# Tracker group is now called 'Main'
	
		map{ $_->{name} = 'Main'} grep{ $_->{name} eq 'Tracker' } @groups_data;
		
		for my $t (@tracks_data){
			$t->{group} =~ s/Tracker/Main/;
			if( $t->{source_select} eq 'soundcard'){
				$t->{source_type} = 'soundcard' ;
				$t->{source_id} = $t->{ch_r}
			}
			elsif( $t->{source_select} eq 'jack'){
				$t->{source_type} = 'jack_client' ;
				$t->{source_id} = $t->{jack_source}
			}
			if( $t->{send_select} eq 'soundcard'){
				$t->{send_type} = 'soundcard' ;
				$t->{send_id} = $t->{ch_m}
			}
			elsif( $t->{send_select} eq 'jack'){
				$t->{send_type} = 'jack_client' ;
				$t->{send_id} = $t->{jack_send}
			}
		}
	}
	if( $saved_version < 0.9986){
	
		map { 	# store insert without intermediate array

				my $t = $_;

				# use new storage format for inserts
				my $i = $t->{inserts};
				if($i =~ /ARRAY/){ 
					$t->{inserts} = scalar @$i ? $i->[0] : {}  }
				
				# initialize inserts effect_chain_stack and cache_map

				$t->{inserts} //= {};
				$t->{effect_chain_stack} //= [];
				$t->{cache_map} //= {};

				# set class for Mastering tracks

				$t->{class} = 'Audio::Nama::MasteringTrack' if $t->{group} eq 'Mastering';
				$t->{class} = 'Audio::Nama::SimpleTrack' if $t->{name} eq 'Master';

				# rename 'ch_count' field to 'width'
				
				$t->{width} = $t->{ch_count};
				delete $t->{ch_count};

				# set Mixdown track width to 2
				
				$t->{width} = 2 if $t->{name} eq 'Mixdown';
				
				# remove obsolete fields
				
				map{ delete $t->{$_} } qw( 
											delay 
											length 
											start_position 
											ch_m 
											ch_r
											source_select 
											jack_source   
											send_select
											jack_send);
		}  @tracks_data;
	}

	# jack_manual is now called jack_port
	if ( $saved_version <= 1){
		map { $_->{source_type} =~ s/jack_manual/jack_port/ } @tracks_data;
	}
	if ( $saved_version <= 1.053){ # convert insert data to object
		my $n = 0;
		@inserts_data = ();
		for my $t (@tracks_data){
			my $i = $t->{inserts};
			next unless keys %$i;
			$t->{postfader_insert} = ++$n;
			$i->{class} = 'Audio::Nama::PostFaderInsert';
			$i->{n} = $n;
			$i->{wet_name} = $t->{name} . "_wet";
			$i->{dry_name} = $t->{name} . "_dry";
			delete $t->{inserts};
			delete $i->{tracks};
			push @inserts_data, $i;
		} 
	}
	if ( $saved_version <= 1.054){ 

		for my $t (@tracks_data){

			# source_type 'track' is now  'bus'
			$t->{source_type} =~ s/track/bus/;

			# convert 'null' bus to 'Null' (which is eliminated below)
			$t->{group} =~ s/null/Null/;
		}

	}

	# get rid of Null bus routing
	
	map{$_->{group}       = 'Main'; 
		$_->{source_type} = 'null';
		$_->{source_id}   = 'null';
  	} grep{$_->{group} eq 'Null'} @tracks_data;

	$debug and print "inserts data", yaml_out \@inserts_data;


	# make sure Master has reasonable output settings
	
	map{ if ( ! $_->{send_type}){
				$_->{send_type} = 'soundcard',
				$_->{send_id} = 1
			}
		} grep{$_->{name} eq 'Master'} @tracks_data;

	#  destroy and recreate all buses

	Audio::Nama::Bus::initialize();	
	create_system_buses(); 
	#map { Audio::Nama::Group->new( %{ $_ } ) } @groups_data;  

	# restore user buses
		
	map{ my $class = $_->{class}; $class->new( %$_ ) } @bus_data;

	# restore user tracks
	
	my $did_apply = 0;

	# temporary turn on mastering mode to enable
	# recreating mastering tracksk

	my $current_master_mode = $mastering_mode;
	$mastering_mode = 1;

	map{ 
		my %h = %$_; 
		my $track = Audio::Nama::Track->new( %h ) ; # initially Audio::Nama::Track 
		if ( $track->class ){ bless $track, $track->class } # current scheme
	} @tracks_data;

	$mastering_mode = $current_master_mode;

	# restore inserts
	
	Audio::Nama::Insert::initialize();
	
	map{ 
		bless $_, $_->{class};
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
			$did_apply++ 
				unless $id eq $ti{$n}->vol
					or $id eq $ti{$n}->pan;
			
			add_effect({
						chain => $cops{$id}->{chain},
						type => $cops{$id}->{type},
						cop_id => $id,
						parent_id => $cops{$id}->{belongs_to},
						});

		}
	} @tracks_data;


	#print "\n---\n", $main->dump;  
	#print "\n---\n", map{$_->dump} Audio::Nama::Track::all();# exit; 
	$did_apply and $ui->manifest;
	$debug and print join " ", 
		(map{ ref $_, $/ } Audio::Nama::Track::all()), $/;


	# restore Alsa mixer settings
	if ( $opts{a} ) {
		my $file = $file; 
		$file =~ s/\.yml$//;
		print "restoring ALSA settings\n";
		print qx(alsactl -f $file.alsa restore);
	}

	# text mode marks 
		
	map{ 
		my %h = %$_; 
		my $mark = Audio::Nama::Mark->new( %h ) ;
	} @marks_data;


	$ui->restore_time_marks();
	$ui->paint_mute_buttons;

	# track fades
	
	map{ 
		my %h = %$_; 
		my $fade = Audio::Nama::Fade->new( %h ) ;
	} @fade_data;


	# restore command history
	
	$term->SetHistory(@command_history);
} 

sub set_track_class {
	my ($track, $class) = @_;
	bless $track, $class;
	$track->set(class => $class);
}

sub process_control_inputs { }

sub set_position {
	my $seconds = shift;
	my $am_running = ( eval_iam('engine-status') eq 'running');
	return if really_recording();
	my $jack = $jack_running;
	#print "jack: $jack\n";
	$am_running and $jack and eval_iam('stop');
	eval_iam("setpos $seconds");
	$am_running and $jack and sleeper($seek_delay), eval_iam('start');
	$ui->clock_config(-text => colonize($seconds));
}

sub forward {
	my $delta = shift;
	my $here = eval_iam('getpos');
	my $new = $here + $delta;
	set_position( $new );
}

sub rewind {
	my $delta = shift;
	forward( -$delta );
}
sub solo {
	my $current_track = $this_track;
	if ($soloing) { all() }

	# get list of already muted tracks if I haven't done so already
	
	if ( ! @already_muted ){
		@already_muted = grep{ $_->old_vol_level} 
                         map{ $tn{$_} } 
						 Audio::Nama::Track::user();
	}
	$debug and say join " ", "already muted:", map{$_->name} @already_muted;

	# mute all tracks
	my @bus_tree = ($this_track->name, $this_track->bus_tree());
	map { $tn{$_}->mute(1) } 
	grep { my $tn = $_; ! grep { $tn eq $_ } @bus_tree } 
	Audio::Nama::Track::user();

	$soloing = 1;
}

sub all {
	
	# unmute all tracks
	map { $tn{$_}->unmute(1) } Audio::Nama::Track::user();

	# re-mute previously muted tracks
	if (@already_muted){
		map { $_->mute(1) } @already_muted;
	}

	# remove listing of muted tracks
	
	@already_muted = ();
	$soloing = 0;
	
}
	

sub pager {
	$debug2 and print "&pager\n";
	my @output = @_;
#	my ($screen_lines, $columns) = split " ", qx(stty size);
	my ($screen_lines, $columns) = $term->get_screen_size();
	my $line_count = 0;
	map{ $line_count += $_ =~ tr(\n)(\n) } @output;
	if ( $use_pager and $line_count > $screen_lines - 2) { 
		my $fh = File::Temp->new();
		my $fname = $fh->filename;
		print $fh @output;
		file_pager($fname);
	} else {
		print @output;
	}
	print "\n\n";
}
sub file_pager {
	$debug2 and print "&file_pager\n";
	my $fname = shift;
	if (! -e $fname or ! -r $fname ){
		carp "file not found or not readable: $fname\n" ;
		return;
    }
	my $pager = $ENV{PAGER} || "/usr/bin/less";
	my $cmd = qq($pager $fname); 
	system $cmd;
}
sub dump_all {
	my $tmp = ".dump_all";
	my $fname = join_path( project_root(), $tmp);
	save_state($fname);
	file_pager("$fname.yml");
}


sub show_io {
	my $output = yaml_out( \%inputs ). yaml_out( \%outputs ); 
	pager( $output );
}

# command line processing routines

sub get_ecasound_iam_keywords {

	my %reserved = map{ $_,1 } qw(  forward
									fw
									getpos
									h
									help
									rewind
									quit
									q
									rw
									s
									setpos
									start
									stop
									t
									?	);
	
	local $debug = 0;
	%iam_cmd = map{$_,1 } 
				grep{ ! $reserved{$_} } split /[\s,]/, eval_iam('int-cmd-list');
}

sub process_line {
	$debug2 and print "&process_line\n";
	my ($user_input) = @_;
	$debug and print "user input: $user_input\n";
	if (defined $user_input and $user_input !~ /^\s*$/) {
		$term->addhistory($user_input) 
			unless $user_input eq $previous_text_command;
		$previous_text_command = $user_input;
		command_process( $user_input );
		reconfigure_engine();
		revise_prompt();
	}
}
sub command_process {
	my $input = shift;
	my $input_was = $input;
	while ($input =~ /\S/) { 
		$debug and say "input: $input";
		$parser->meta(\$input) or print("bad command: $input_was\n"), last;
	}
	$ui->refresh; # in case we have a graphic environment
	set_current_bus();
}


sub leading_track_spec {
	my $cmd = shift;
	if( my $track = $tn{$cmd} || $ti{$cmd} ){
		$debug and print "Selecting track ",$track->name,"\n";
		$this_track = $track;
		ecasound_select_chain( $this_track->n );
		1;
	}
		
}
sub ecasound_select_chain {
	my $n = shift;
	my $cmd = "c-select $n";

	if( 

		# specified chain exists in the chain setup
		$is_ecasound_chain{$n}

		# engine is configured
		and eval_iam( 'cs-connected' ) =~ /$chain_setup_file/

	){ 	eval_iam($cmd); 
		return 1 

	} else { 
		$debug and carp 
			"c-select $n: attempted to select non-existing Ecasound chain\n"; 
		return 0
	}
}
sub set_current_bus {
	my $track = shift || ($this_track ||= $tn{Master});
	if( $track->name =~ /Master|Mixdown/){ $this_bus = 'Main' }
	elsif( $Audio::Nama::Bus::by_name{$track->name} ){$this_bus = $track->name }
	else { $this_bus = $track->group }
}
sub eval_perl {
	my $code = shift;
	my (@result) = eval $code;
	print( "Perl command failed: $@\n") if $@;
	pager(join "\n", @result) unless $@;
	print "\n";
}	

sub is_bunch {
	my $name = shift;
	$Audio::Nama::Bus::by_name{$name} or $bunch{$name}
}
my %set_stat = ( 
				 (map{ $_ => 'rw' } qw(rec mon off) ), 
				 map{ $_ => 'rec_status' } qw(REC MON OFF)
				 );

sub bunch_tracks {
	my $bunchy = shift;
	my @tracks;
	if ( my $bus = $Audio::Nama::Bus::by_name{$bunchy}){
		@tracks = $bus->tracks;
	} elsif ( $bunchy eq 'bus' ){
		$debug and print "special bunch: bus\n";
		@tracks = grep{ ! $Audio::Nama::Bus::by_name{$_} } $Audio::Nama::Bus::by_name{$this_bus}->tracks;
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
				$Audio::Nama::Bus::by_name{$this_bus}->tracks
	} elsif ( $bunch{$bunchy} and @tracks = @{$bunch{$bunchy}}  ) {
		$debug and print "bunch tracks: @tracks\n";
	} else { say "$bunchy: no matching bunch identifier found" }
	@tracks;
}
sub track_from_name_or_index { /\D/ ? $tn{$_[0]} : $ti{$_[0]}  }
	
sub load_keywords {
	@keywords = keys %commands;
	push @keywords, grep{$_} map{split " ", $commands{$_}->{short}} @keywords;
	push @keywords, keys %iam_cmd;
	push @keywords, keys %effect_j;
	push @keywords, "Audio::Nama::";
}

sub complete {
    my ($text, $line, $start, $end) = @_;
#	print join $/, $text, $line, $start, $end, $/;
    return $term->completion_matches($text,\&keyword);
};

{ 	my $i;
sub keyword {
        my ($text, $state) = @_;
        return unless $text;
        if($state) {
            $i++;
        }
        else { # first call
            $i = 0;
        }
        for (; $i<=$#keywords; $i++) {
            return $keywords[$i] if $keywords[$i] =~ /^\Q$text/;
        };
        return undef;
} };


sub jack_update {
	# cache current JACK status
	$jack_running = jack_running();
	my $jack_lsp = qx(jack_lsp -Ap 2> /dev/null); 
	%jack = %{jack_ports($jack_lsp)} if $jack_running;
}
sub jack_client {

	# returns array of ports if client and direction exist
	
	my ($name, $direction)  = @_;
	$jack{$name}{$direction} // []
}

sub jack_ports {
	my $j = shift || $jack_lsp; 
	#say "jack_lsp: $j";

	# convert to single lines

	$j =~ s/\n\s+/ /sg;

	# system:capture_1 alsa_pcm:capture_1 properties: output,physical,terminal,
	#fluidsynth:left properties: output,
	#fluidsynth:right properties: output,
	my %jack = ();

	map{ 
		my ($direction) = /properties: (input|output)/;
		s/properties:.+//;
		my @port_aliases = /
			\s* 			# zero or more spaces
			([^:]+:[^:]+?) # non-colon string, colon, non-greey non-colon string
			(?=[-+.\w]+:|\s+$) # zero-width port name or spaces to end-of-string
		/gx;
		map { 
				s/ $//; # remove trailing space
				$jack{ $_ }{ $direction }++;
				my ($client, $port) = /(.+?):(.+)/;
				push @{ $jack{ $client }{ $direction } }, $_; 

		 } @port_aliases;

	} split "\n",$j;
	#print yaml_out \%jack;
	\%jack
}
	

sub automix {

	# get working track set
	
	my @tracks = grep{
					$tn{$_}->rec_status eq 'MON' or
					$Audio::Nama::Bus::by_name{$_} and $tn{$_}->rec_status eq 'REC'
				 } $main->tracks;

	say "tracks: @tracks";

	## we do not allow automix if inserts are present	

	say("Cannot perform automix if inserts are present. Skipping."), return
		if grep{$tn{$_}->prefader_insert || $tn{$_}->postfader_insert} @tracks;

	#use Smart::Comments '###';
	# add -ev to summed signal
	my $ev = add_effect( { chain => $tn{Master}->n, type => 'ev' } );
	### ev id: $ev

	# turn off audio output
	
	$main_out = 0;

	### Status before mixdown:

	command_process('show');

	
	### reduce track volume levels  to 10%

	## accommodate ea and eadb volume controls

	my $vol_operator = $cops{$tn{$tracks[0]}->vol}{type};

	my $reduce_vol_command  = $vol_operator eq 'ea' ? 'vol / 10' : 'vol - 10';
	my $restore_vol_command = $vol_operator eq 'ea' ? 'vol * 10' : 'vol + 10';

	### reduce vol command: $reduce_vol_command

	for (@tracks){ command_process("$_  $reduce_vol_command") }

	command_process('show');

	generate_setup('automix') # pass a bit of magic
		or say("automix: generate_setup failed!"), return;
	connect_transport();
	
	# start_transport() does a rec_cleanup() on transport stop
	
	eval_iam('start'); # don't use heartbeat
	sleep 2; # time for engine to stabilize
	while( eval_iam('engine-status') ne 'finished'){ 
		print q(.); sleep 1; update_clock_display()}; 
	print " Done\n";

	# parse cop status
	my $cs = eval_iam('cop-status');
	### cs: $cs
	my $cs_re = qr/Chain "1".+?result-max-multiplier ([\.\d]+)/s;
	my ($multiplier) = $cs =~ /$cs_re/;

	### multiplier: $multiplier

	remove_effect($ev);

	# deal with all silence case, where multiplier is 0.00000
	
	if ( $multiplier < 0.00001 ){

		say "Signal appears to be silence. Skipping.";
		for (@tracks){ command_process("$_  $restore_vol_command") }
		$main_out = 1;
		return;
	}

	### apply multiplier to individual tracks

	for (@tracks){ command_process( "$_ vol*$multiplier" ) }

	# $main_out = 1; # unnecessary: mixdown will turn off and turn on main out
	
	### mixdown
	command_process('mixdown; arm; start');

	### turn on audio output

	# command_process('mixplay'); # rec_cleanup does this automatically

	#no Smart::Comments;
	
}

sub master_on {

	return if $mastering_mode;
	
	# set $mastering_mode	
	
	$mastering_mode++;

	# create mastering tracks if needed
	
	if ( ! $tn{Eq} ){  
	
		my $old_track = $this_track;
		add_mastering_tracks();
		add_mastering_effects();
		$this_track = $old_track;
	} else { 
		unhide_mastering_tracks();
		map{ $ui->track_gui($tn{$_}->n) } @mastering_track_names;
	}

}
	
sub master_off {

	$mastering_mode = 0;
	hide_mastering_tracks();
	map{ $ui->remove_track_gui($tn{$_}->n) } @mastering_track_names;
	$this_track = $tn{Master} if grep{ $this_track->name eq $_} @mastering_track_names;
;
}


sub add_mastering_tracks {

	map{ 
		my $track = Audio::Nama::MasteringTrack->new(
			name => $_,
			rw => 'MON',
			group => 'Mastering', 
		);
		$ui->track_gui( $track->n );

 	} grep{ $_ ne 'Boost' } @mastering_track_names;
	my $track = Audio::Nama::SlaveTrack->new(
		name => 'Boost', 
		rw => 'MON',
		group => 'Mastering', 
		target => 'Master',
	);
	$ui->track_gui( $track->n );

	
}

sub add_mastering_effects {
	
	$this_track = $tn{Eq};

	command_process("add_effect $eq");

	$this_track = $tn{Low};

	command_process("add_effect $low_pass");
	command_process("add_effect $compressor");
	command_process("add_effect $spatialiser");

	$this_track = $tn{Mid};

	command_process("add_effect $mid_pass");
	command_process("add_effect $compressor");
	command_process("add_effect $spatialiser");

	$this_track = $tn{High};

	command_process("add_effect $high_pass");
	command_process("add_effect $compressor");
	command_process("add_effect $spatialiser");

	$this_track = $tn{Boost};
	
	command_process("add_effect $limiter"); # insert after vol
}

sub unhide_mastering_tracks {
	command_process("for Mastering; set hide 0");
}

sub hide_mastering_tracks {
	command_process("for Mastering; set hide 1");
 }
		
# vol/pan requirements of mastering and mixdown tracks

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

# track width in words

sub width {
	my $count = shift;
	return 'mono' if $count == 1;
	return 'stereo' if $count == 2;
	return "$count channels";
}

sub effect_code {
	# get text effect code from user input, which could be
	# - LADSPA Unique ID (number)
	# - LADSPA Label (el:something)
	# - abbreviated LADSPA label (something)
	# - Ecasound operator (something)
	# - abbreviated Ecasound preset (something)
	# - Ecasound preset (pn:something)
	
	# there is no interference in these labels at present,
	# so we offer the convenience of using them without
	# el: and pn: prefixes.
	
	my $input = shift;
	my $code;
    if ($input !~ /\D/){ # i.e. $input is all digits
		$code = $ladspa_label{$input} 
			or carp("$input: LADSPA plugin not found.  Aborting.\n"), return;
	}
	elsif ( $effect_i{$input} ) { $code = $input } 
	elsif ( $effect_j{$input} ) { $code = $effect_j{$input} }
	else { warn "effect code not found: $input\n";}
	$code;
}
	# status_snapshot() 
	#
	# hashref output for detecting if we need to reconfigure engine
	# compared as YAML strings
	#
{
	my @sense_reconfigure = qw(
		name
		width
		group 
		playat
		region_start	
		region_end
		looping
		source_id
		source_type
		send_id
		send_type
		rec_defeat
		inserts
		rec_status
		current_version
 );
sub status_snapshot {

	
	my %snapshot = ( project 		=> 	$project_name,
					 mastering_mode => $mastering_mode,
					 preview        => $preview,
					 main_out 		=> $main_out,
					 jack_running	=> $jack_running,
					 tracks			=> [], );
	map { push @{$snapshot{tracks}}, $_->snapshot(\@sense_reconfigure) }
	Audio::Nama::Track::all();
	\%snapshot;
}
}
sub set_region {
	my ($beg, $end) = @_;
	$this_track->set(region_start => $beg);
	$this_track->set(region_end => $end);
	Audio::Nama::Text::show_region();
}
sub new_region {
	my ($beg, $end, $name) = @_;
	$name ||= new_region_name();
	add_track_alias($name, $this_track->name);	
	set_region($beg,$end);
}
sub new_region_name {
	my $name = $this_track->name . '_region_';
	my $i;
	map{ my ($j) = /_(\d+)$/; $i = $j if $j > $i; }
		grep{/$name/} keys %Audio::Nama::Track::by_name;
	$name . ++$i
}
sub remove_region {
	if (! $this_track->region_start){
		say $this_track->name, ": no region is defined. Skipping.";
		return;
	} elsif ($this_track->target ){
		say $this_track->name, ": looks like a region...  removing.";
		$this_track->remove;
	} else { undefine_region() }
}
	
sub undefine_region {
	$this_track->set(region_start => undef );
	$this_track->set(region_end => undef );
	print $this_track->name, ": Region definition removed. Full track will play.\n";
}

sub add_sub_bus {
	my ($name, $type, $id, @args) = @_; 
		# command add_sub_bus does not supply @args at present
	
	Audio::Nama::SubBus->new( 
		name => $name, 
		send_type => $type // 'bus',
		send_id	 => $id // $name,
		);
	# create mix track
	my @vals = (source_type => 'bus', 
				source_id 	=> 'bus',
				width		=> 2, # default to stereo 
				rec_defeat 	=> 1,
				@args);

	if ($tn{$name}){
		say qq($name: setting as mix track for bus "$name");
		$tn{$name}->set( @vals );

	} else { Audio::Nama::add_track($name, @vals); }
}
	
sub add_send_bus {

	my ($name, $dest_id, $bus_type) = @_;
	my $dest_type = dest_type( $dest_id );

	# dest_type: soundcard | jack_client | loop | jack_port | jack_multi
	
	print "name: $name: dest_type: $dest_type dest_id: $dest_id\n";

	if ($Audio::Nama::Bus::by_name{$name}){
		say qq(monitor bus "$name" already exists. Updating with new tracks.");

	} else {
	my @args = (
		name => $name, 
		send_type => $dest_type,
		send_id	 => $dest_id,
	);

	my $class = $bus_type eq 'cooked' ? 'Audio::Nama::SendBusCooked' : 'Audio::Nama::SendBusRaw';
	my $bus = $class->new( @args );

	$bus or carp("can't create bus!\n"), return;

	}
	map{ Audio::Nama::SlaveTrack->new(	name => "$name\_$_", # BusName_TrackName
							rw => 'MON',
							target => $_,
							group  => $name,
						)
   } $main->tracks;
		
}

sub dest_type { 
	my $dest = shift;
	if (defined $dest and ($dest !~ /\D/))        { 'soundcard' } # digits only
	elsif ($dest =~ /^loop,/) { 'loop' }
	elsif ($dest =~ /^\w+\.ports/){ 'jack_port' }
	elsif ($dest){  # any string 
		#carp( "$dest: jack_client doesn't exist.\n") unless jack_client($dest);
		'jack_client' ; }
	else { undef }
}
	
sub update_send_bus {
	my $name = shift;
		add_send_bus( $name, 
						 $Audio::Nama::Bus::by_name{$name}->destination_id),
						 "dummy",
}

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
	say("no effects to store"), return unless $track->fancy_ops;
	my $save_name   = $vals{save} || private_effect_chain_name();
	$debug and say "save name: $save_name"; 
	new_effect_chain( $track, $save_name ); # current track effects
	push @{ $track->effect_chain_stack }, $save_name;
	map{ remove_effect($_)} $track->fancy_ops;
	$save_name;
}

sub pop_effect_chain { # restore previous
	$debug2 and say "&pop_effect_chain";
	my $track = shift;
	my $previous = pop @{$track->effect_chain_stack};
	say ("no previous effect chain"), return unless $previous;
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
	while( my $name = each %effect_profile){
		say "effect profile: $name";
		list_effect_chains("_$name:");
	}
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
	say ("$name: effect chain does not exist"), return 
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
	map{ my $name = $_;
		print join ' ', "$name:", 
		map{$effect_chain{$name}{type}{$_},
			@{$effect_chain{$name}{params}{$_}}
		} @{$effect_chain{$name}{ops}};
		print "\n";
	} @ids;
}
sub cleanup_exit {
 	remove_small_wavs();
 	kill 15, ecasound_pid() if $sock;  	
	$term->rl_deprep_terminal();
	CORE::exit; 
}


{ my ($orig_version, $cooked);
sub cache_track { # launch subparts if conditions are met
	my $track = shift;
	say $track->name, ": preparing to cache.";
	
	# abort warning if necessary when sub-bus mix track
	if( $Audio::Nama::Bus::by_name{$track->name} ){ 
		$track->rec_status ne 'OFF' or say(
			"mix track ",$track->name, ": status is OFF. Aborting."), return;

	# abort warning if necessary when normal track
	} else { 
		$track->rec_status eq 'MON' or say(
			$track->name, ": track caching requires MON status. Aborting."), return;
	}
	say($track->name, ": no effects to cache!  Skipping."), return 
		unless 	$track->fancy_ops 
				or $track->has_insert
				or $Audio::Nama::Bus::by_name{$track->name};

	prepare_to_cache($track);
	complete_caching($track);
}

sub prepare_to_cache {
	my $track = shift;
 	initialize_chain_setup_vars();
	$orig_version = $track->monitor_version;
	my $cooked_name = $track->name . '_cooked';
	my $cooked = Audio::Nama::CacheRecTrack->new(
		name => $cooked_name,
		group => 'Temp',
		target => $track->name,
	);
	# output path
	$g->add_path($track->name, $cooked->name, 'wav_out');

	# input path when $track->rec_status MON
	$g->add_path('wav_in',$track->name) if $track->rec_status eq 'MON';
	$g->set_vertex_attributes(
		$cooked->name, 
		{ format => signal_format($cache_to_disk_format,$cooked->width),
		}
	); 

	$debug and say "The graph is:\n$g";

	# input paths: sub buses (significant when
	# $track->rec_status is REC and track is a sub-bus mix track)
	map{ $_->apply() } grep{ (ref $_) =~ /Sub/ } Audio::Nama::Bus::all();

	$debug and say "The graph1 is:\n$g";
	prune_graph();
	$debug and say "The graph2 is:\n$g";
	Audio::Nama::Graph::expand_graph($g); 
	$debug and say "The graph3 is:\n$g";
	Audio::Nama::Graph::add_inserts($g);
	$debug and say "The graph4 is:\n$g";
	process_routing_graph(); 
	write_chains();
	remove_temporary_tracks();
}
sub complete_caching {
	my $track = shift;
	connect_transport('no_transport_status')
		or say ("Couldn't connect engine! Aborting."), return;
	say $/,$track->name,": length ". d2($length). " seconds";
	say "Starting cache operation. Please wait.";
	eval_iam("cs-set-length $length"); # to longest input object
	eval_iam("start");
	sleep 2; # time for transport to stabilize
	while( eval_iam('engine-status') ne 'finished'){ 
	print q(.); sleep 2; update_clock_display() } ; print " Done\n";
	my $name = $track->name;
	my @files = grep{/$name/} new_files_were_recorded();
	if (@files ){ 
		$debug and say "updating track cache_map";
		#say "cache map",yaml_out($track->cache_map);
		my $cache_map = $track->cache_map;
		$cache_map->{$track->last} = { 
			original 			=> $orig_version,
			effect_chain	=> push_effect_chain($track), # bypass
		};
		pop @{$track->effect_chain_stack}; # we keep it elsewhere
		if ($track->has_insert){
			say "removing insert... ";
			say "if you want it again you will need to replace it yourself";
			say "this is what it was";
			say yaml_out( $track->inserts );
			$track->remove_insert;
		}
		#say "cache map",yaml_out($track->cache_map);
		say qq(Saving effects for cached track "$name".
'uncache' will restore effects and set version $orig_version\n);

		

		# special handling for sub-bus mix track
		
		if ($track->rec_status eq 'REC'){ 
			$track->set(rw => 'MON');
			$ui->global_version_buttons(); # recreate
			$ui->refresh();

		# usual post-record handling is the default
	
		} else { post_rec_configure() }

		reconfigure_engine();

	} else { say "track cache operation failed!"; }
}
}
sub uncache_track { 
	my $track = shift;
	# skip unless MON;
	my $cache_map = $track->cache_map;
	my $version = $track->monitor_version;
	if(is_cached($track)){
		# blast away any existing effects, TODO: warn or abort	
		say $track->name, ": removing effects (except vol/pan)" if $track->fancy_ops;
		map{ remove_effect($_)} $track->fancy_ops;

		# original WAV -> WAV case: reset version 
		if ( $cache_map->{$version}{original} ){ 
			$track->set(active => $cache_map->{$version}{original});
			print $track->name, ": setting uncached version ", $track->active, $/;

		# assume a sub-bus mix track, i.e. REC -> WAV: set to REC
		} else { 
			$track->set(rw => 'REC') ;
			say $track->name, ": setting sub-bus mix track to REC";
		} 

		add_effect_chain($track, $cache_map->{$version}{effect_chain})
			if $cache_map->{$version}{effect_chain};
	} 
	else { print $track->name, ": version $version is not cached\n"}
}
sub is_cached {
	my $track = shift;
	my $cache_map = $track->cache_map;
	$cache_map->{$track->monitor_version}
}
	
sub do_script {
	say "hello script";
	my $name = shift;
	my $file;
	if( $name =~ m!/!){ $file = $name }
	else {
		$file = join_path(project_dir(),$name);
		if(-e $file){}
		else{ $file = join_path(project_root(),$name) }
	}
	-e $file or say("$file: file not found. Skipping"), return;
	my @lines = split "\n",io($file)->all;
	my $old_opt_r = $opts{R};
	$opts{R} = 1; # turn off auto reconfigure
	for my $input (@lines) { process_line($input)};
	$opts{R} = $old_opt_r;
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
		print "Unlinking.\n";
		unlink $wav or warn "couldn't unlink $wav: $!\n";
		rememoize();
	}
	$term->remove_history($term->where_history);
	$main->set(rw => $old_group_status);
	1;
}

sub some_user_tracks {
	my $which = shift;
	my @user_tracks = Audio::Nama::Track::all();
	splice @user_tracks, 0, 2; # drop Master and Mixdown tracks
	return unless @user_tracks;
	my @selected_user_tracks = grep { $_->rec_status eq $which } @user_tracks;
	return unless @selected_user_tracks;
	map{ $_->n } @selected_user_tracks;
}
sub user_rec_tracks { some_user_tracks('REC') }
sub user_mon_tracks { some_user_tracks('MON') }

sub ecasound_get_info {
	my ($path, $command) = @_;
	eval_iam('cs-disconnect') if eval_iam('cs-connected');
	eval_iam('cs-remove') if eval_iam('cs-selected');
	eval_iam('cs-add gl');
	eval_iam('c-add g');
	eval_iam('ai-add ' . $path);
	eval_iam('ao-add null');
	eval_iam('cs-connect');
	eval_iam('ai-select '. $path);
	my $result = eval_iam($command);
	eval_iam('cs-disconnect');
	eval_iam('cs-remove');
	$result;
}
sub get_length { 
	my $path = shift;
	my $length = ecasound_get_info($path, 'ai-get-length');
	sprintf("%.4f", $length);
}
sub get_format {
	my $path = shift;
	ecasound_get_info($path, 'ai-get-format');
}
sub freq { [split ',', $_[0] ]->[2] }  # e.g. s16_le,2,44100

sub channels { [split ',', $_[0] ]->[1] }
	

### end


# gui handling
#
sub init_gui {

	$debug2 and print "&init_gui\n";

	init_palettefields(); # keys only


	### 	Tk root window 

	# Tk main window
 	$mw = MainWindow->new;  
	get_saved_colors();
	$mw->optionAdd('*font', 'Helvetica 12');
	$mw->optionAdd('*BorderWidth' => 1);
	$mw->title("Ecasound/Nama"); 
	$mw->deiconify;
	$parent{mw} = $mw;

	### init effect window

	$ew = $mw->Toplevel;
	$ew->title("Effect Window");
	$ew->deiconify; 
#	$ew->withdraw;
	$parent{ew} = $ew;

	### Exit via Ctrl-C 

	$mw->bind('<Control-Key-c>' => \&cleanup_exit); 
	$ew->bind('<Control-Key-c>' => \&cleanup_exit);

    ## Press SPACE to start/stop transport

	$mw->bind('<Control-Key- >' => \&toggle_transport); 
	$ew->bind('<Control-Key- >' => \&toggle_transport); 
	
	$canvas = $ew->Scrolled('Canvas')->pack;
	$canvas->configure(
		scrollregion =>[2,2,10000,10000],
		-width => 1200,
		-height => 700,	
		);
	$effect_frame = $canvas->Frame;
	my $id = $canvas->createWindow(30,30, -window => $effect_frame,
											-anchor => 'nw');

	$project_label = $mw->Label->pack(-fill => 'both');

	$time_frame = $mw->Frame(
	#	-borderwidth => 20,
	#	-relief => 'groove',
	)->pack(
		-side => 'bottom', 
		-fill => 'both',
	);
	$mark_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	$fast_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	$transport_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	# $oid_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$clock_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	#$group_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
 	my $track_canvas = $mw->Scrolled('Canvas')->pack(-side => 'bottom', -fill => 'both');
 	$track_canvas->configure(
 		-scrollregion =>[2,2,400,9600],
 		-width => 400,
 		-height => 400,	
 		);
	$track_frame = $track_canvas->Frame; # ->pack(-fill => 'both');
	#$track_frame = $mw->Frame;
 	my $id2 = $track_canvas->createWindow(0,0,
		-window => $track_frame, 
		-anchor => 'nw');
 	#$group_label = $group_frame->Menubutton(-text => "GROUP",
 #										-tearoff => 0,
 #										-width => 13)->pack(-side => 'left');
		
	$add_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$perl_eval_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$iam_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$load_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
#	my $blank = $mw->Label->pack(-side => 'left');



	$sn_label = $load_frame->Label(
		-text => "    Project name: "
	)->pack(-side => 'left');
	$sn_text = $load_frame->Entry(
		-textvariable => \$project,
		-width => 25
	)->pack(-side => 'left');

	$sn_load = $load_frame->Button->pack(-side => 'left');;
	$sn_new = $load_frame->Button->pack(-side => 'left');;
	$sn_quit = $load_frame->Button->pack(-side => 'left');
	$sn_save = $load_frame->Button->pack(-side => 'left');
	my $sn_save_text = $load_frame->Entry(
									-textvariable => \$save_id,
									-width => 15
									)->pack(-side => 'left');
	$sn_recall = $load_frame->Button->pack(-side => 'left');
	$sn_palette = $load_frame->Menubutton(-tearoff => 0)
		->pack( -side => 'left');
	$sn_namapalette = $load_frame->Menubutton(-tearoff => 0)
		->pack( -side => 'left');
	#$sn_effects_palette = $load_frame->Menubutton(-tearoff => 0)
	#	->pack( -side => 'left');
	# $sn_dump = $load_frame->Button->pack(-side => 'left');

	$build_track_label = $add_frame->Label(
		-text => "New track name: ")->pack(-side => 'left');
	$build_track_text = $add_frame->Entry(
		-textvariable => \$track_name, 
		-width => 12
	)->pack(-side => 'left');
# 	$build_track_mon_label = $add_frame->Label(
# 		-text => "Aux send: (channel/client):",
# 		-width => 18
# 	)->pack(-side => 'left');
# 	$build_track_mon_text = $add_frame->Entry(
# 		-textvariable => \$ch_m, 
# 		-width => 10
# 	)->pack(-side => 'left');
	$build_track_rec_label = $add_frame->Label(
		-text => "Input channel or client:"
	)->pack(-side => 'left');
	$build_track_rec_text = $add_frame->Entry(
		-textvariable => \$ch_r, 
		-width => 10
	)->pack(-side => 'left');
	$build_track_add_mono = $add_frame->Button->pack(-side => 'left');;
	$build_track_add_stereo  = $add_frame->Button->pack(-side => 'left');;

	$sn_load->configure(
		-text => 'Load',
		-command => sub{ load_project(
			name => remove_spaces($project),
			)});
	$sn_new->configure( 
		-text => 'Create',
		-command => sub{ load_project(
							name => remove_spaces($project),
							create => 1)});
	$sn_save->configure(
		-text => 'Save settings',
		-command => #sub { print "save_id: $save_id\n" });
		 sub {save_state($save_id) });
	$sn_recall->configure(
		-text => 'Recall settings',
 		-command => sub {load_project (name => $project_name, 
 										settings => $save_id)},
				);
	$sn_quit->configure(-text => "Quit",
		 -command => sub { 
				return if transport_running();
				save_state($save_id);
				print "Exiting... \n";		
				#$term->tkRunning(0);
				#$ew->destroy;
				#$mw->destroy;
				#Audio::Nama::Text::command_process('quit');
				exit;
				 });
	$sn_palette->configure(
		-text => 'Palette',
		-relief => 'raised',
	);
	$sn_namapalette->configure(
		-text => 'Nama palette',
		-relief => 'raised',
	);
# 	$sn_effects_palette->configure(
# 		-text => 'Effects palette',
# 		-relief => 'raised',
# 	);

my @color_items = map { [ 'command' => $_, 
							-command  => colorset('mw', $_ ) ]
						} @palettefields;
$sn_palette->AddItems( @color_items);

@color_items = map { [ 'command' => $_, 
							-command  => namaset( $_ ) ]
						} @namafields;

# $sn_effects_palette->AddItems( @color_items);
# 
# @color_items = map { [ 'command' => $_, 
# 						-command  => namaset($_, $namapalette{$_})]
# 						} @namafields;
$sn_namapalette->AddItems( @color_items);

	$build_track_add_mono->configure( 
			-text => 'Add Mono Track',
			-command => sub { 
					return if $track_name =~ /^\s*$/;	
			add_track(remove_spaces($track_name)) }
	);
	$build_track_add_stereo->configure( 
			-text => 'Add Stereo Track',
			-command => sub { 
								return if $track_name =~ /^\s*$/;	
								add_track(remove_spaces($track_name));
								Audio::Nama::Text::command_process('stereo');
	});

	my @labels = 
		qw(Track Name Version Status Source Send Volume Mute Unity Pan Center Effects);
	my @widgets;
	map{ push @widgets, $track_frame->Label(-text => $_)  } @labels;
	$widgets[0]->grid(@widgets[1..$#widgets]);


#  unified command processing by command_process 
# 	
 	$iam_label = $iam_frame->Label(
# 	-text => "         Command: "
 		)->pack(-side => 'left');;
# 	$iam_text = $iam_frame->Entry( 
# 		-textvariable => \$iam, -width => 45)
# 		->pack(-side => 'left');;
# 	$iam_execute = $iam_frame->Button(
# 			-text => 'Execute',
# 			-command => sub { Audio::Nama::Text::command_process( $iam ) }
# 			
# 		)->pack(-side => 'left');;
# 
# 			#join  " ",
# 			# grep{ $_ !~ add fxa afx } split /\s*;\s*/, $iam) 
		
}

sub transport_gui {
	@_ = discard_object(@_);
	$debug2 and print "&transport_gui\n";

	$transport_label = $transport_frame->Label(
		-text => 'TRANSPORT',
		-width => 12,
		)->pack(-side => 'left');;
	# disable Arm button
	# $transport_setup_and_connect  = $transport_frame->Button->pack(-side => 'left');;
	$transport_start = $transport_frame->Button->pack(-side => 'left');
	$transport_stop = $transport_frame->Button->pack(-side => 'left');
	#$transport_setup = $transport_frame->Button->pack(-side => 'left');;
	#$transport_connect = $transport_frame->Button->pack(-side => 'left');;
	#$transport_disconnect = $transport_frame->Button->pack(-side => 'left');;
	# $transport_new = $transport_frame->Button->pack(-side => 'left');;

	$transport_stop->configure(-text => "Stop",
	-command => sub { 
					stop_transport();
				}
		);
	$transport_start->configure(
		-text => "Start",
		-command => sub { 
		return if transport_running();
		my $color = engine_mode_color();
		project_label_configure(-background => $color);
		start_transport();
				});
# 	$transport_setup_and_connect->configure(
# 			-text => 'Arm',
# 			-command => sub {arm()}
# 						 );

# preview_button();
#mastering_button();

}
sub time_gui {
	@_ = discard_object(@_);
	$debug2 and print "&time_gui\n";

	my $time_label = $clock_frame->Label(
		-text => 'TIME', 
		-width => 12);
	#print "bg: $namapalette{ClockBackground}, fg:$namapalette{ClockForeground}\n";
	$clock = $clock_frame->Label(
		-text => '0:00', 
		-width => 8,
		-background => $namapalette{ClockBackground},
		-foreground => $namapalette{ClockForeground},
		);
	my $length_label = $clock_frame->Label(
		-text => 'LENGTH',
		-width => 10,
		);
	$setup_length = $clock_frame->Label(
	#	-width => 8,
		);

	for my $w ($time_label, $clock, $length_label, $setup_length) {
		$w->pack(-side => 'left');	
	}

	$mark_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	my $fast_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	# jump

	my $jump_label = $fast_frame->Label(-text => q(JUMP), -width => 12);
	my @pluses = (1, 5, 10, 30, 60);
	my @minuses = map{ - $_ } reverse @pluses;
	my @fw = map{ my $d = $_; $fast_frame->Button(
			-text => $d,
			-command => sub { jump($d) },
			)
		}  @pluses ;
	my @rew = map{ my $d = $_; $fast_frame->Button(
			-text => $d,
			-command => sub { jump($d) },
			)
		}  @minuses ;
	my $beg = $fast_frame->Button(
			-text => 'Beg',
			-command => \&to_start,
			);
	my $end = $fast_frame->Button(
			-text => 'End',
			-command => \&to_end,
			);

	$time_step = $fast_frame->Button( 
			-text => 'Sec',
			);
		for my $w($jump_label, @rew, $beg, $time_step, $end, @fw){
			$w->pack(-side => 'left')
		}

	$time_step->configure (-command => sub { &toggle_unit; &show_unit });

	# Marks
	
	my $mark_label = $mark_frame->Label(
		-text => q(MARK), 
		-width => 12,
		)->pack(-side => 'left');
		
	my $drop_mark = $mark_frame->Button(
		-text => 'Place',
		-command => \&drop_mark,
		)->pack(-side => 'left');	
		
	$mark_remove = $mark_frame->Button(
		-text => 'Remove',
		-command => \&arm_mark_toggle,
	)->pack(-side => 'left');	

}

#  the following is based on previous code for multiple buttons
#  needs cleanup

sub preview_button {  
	$debug2 and print "&preview\n";
	@_ = discard_object(@_);
	#my $outputs = $oid_frame->Label(-text => 'OUTPUTS', -width => 12);
	my $oid_button = $transport_frame->Button( );
	$oid_button->configure(
		-text => 'Preview',
		-command => sub { 
			if ($preview ){ # set normal
			} else { # set preview 
			}
			$oid_button->configure( 
		-background => 
				$preview ? $old_bg : $namapalette{Preview} ,
		-text => 
				$preview ? 'Preview' : 'PREVIEW MODE'
					
					);
			});
		push @widget_o, $oid_button;
		
	map { $_ -> pack(-side => 'left') } (@widget_o);
	
}
sub paint_button {
	@_ = discard_object(@_);
	my ($button, $color) = @_;
	$button->configure(-background => $color,
						-activebackground => $color);
}

sub engine_mode_color {
		if ( user_rec_tracks()  ){ 
				$rec  					# live recording
		} elsif ( &really_recording ){ 
				$namapalette{Mixdown}	# mixdown only 
		} elsif ( user_mon_tracks() ){  
				$namapalette{Play}; 	# just playback
		} else { $old_bg } 
	}

sub flash_ready {

	my $color = engine_mode_color();
	$debug and print "flash color: $color\n";
	length_display(-background => $color);
	project_label_configure(-background => $color) unless $preview;
 	$event_id{heartbeat} = AE::timer(5, 0, \&reset_engine_mode_color_display);
}
sub reset_engine_mode_color_display { project_label_configure(-background => $off) }
sub set_engine_mode_color_display { project_label_configure(-background => engine_mode_color()) }
sub group_gui {  
	@_ = discard_object(@_);
	my $group = $main; 
	my $dummy = $track_frame->Label(-text => ' '); 
	$group_label = 	$track_frame->Label(
			-text => "G R O U P",
			-foreground => $namapalette{GroupForeground},
			-background => $namapalette{GroupBackground},

 );
	$group_version = $track_frame->Menubutton( 
		-text => q( ), 
		-tearoff => 0,
		-foreground => $namapalette{GroupForeground},
		-background => $namapalette{GroupBackground},
);
	$group_rw = $track_frame->Menubutton( 
		-text    => $group->rw,
	 	-tearoff => 0,
		-foreground => $namapalette{GroupForeground},
		-background => $namapalette{GroupBackground},
);


		
		$group_rw->AddItems([
			'command' => 'REC',
			-background => $old_bg,
			-command => sub { 
				return if eval_iam("engine-status") eq 'running';
				$group->set(rw => 'REC');
				$group_rw->configure(-text => 'REC');
				refresh();
				reconfigure_engine()
				}
			],[
			'command' => 'MON',
			-background => $old_bg,
			-command => sub { 
				return if eval_iam("engine-status") eq 'running';
				$group->set(rw => 'MON');
				$group_rw->configure(-text => 'MON');
				refresh();
				reconfigure_engine()
				}
			],[
			'command' => 'OFF',
			-background => $old_bg,
			-command => sub { 
				return if eval_iam("engine-status") eq 'running';
				$group->set(rw => 'OFF');
				$group_rw->configure(-text => 'OFF');
				refresh();
				reconfigure_engine()
				}
			]);
			$dummy->grid($group_label, $group_version, $group_rw);
			$ui->global_version_buttons;

}
sub global_version_buttons {
	local $debug = 0;
	my $version = $group_version;
	$version and map { $_->destroy } $version->children;
		
	$debug and print "making global version buttons range:",
		join ' ',1..$main->last, " \n";

			$version->radiobutton( 

				-label => (''),
				-value => 0,
				-command => sub { 
					$main->set(version => 0); 
					$version->configure(-text => " ");
					reconfigure_engine();
					refresh();
					}
			);

 	for my $v (1..$main->last) { 

	# the highest version number of all tracks in the
	# $main group
	
	my @user_track_indices = grep { $_ > 2 } map {$_->n} Audio::Nama::Track::all;
	
		next unless grep{  grep{ $v == $_ } @{ $ti{$_}->versions } }
			@user_track_indices;
		

			$version->radiobutton( 

				-label => ($v ? $v : ''),
				-value => $v,
				-command => sub { 
					$main->set(version => $v); 
					$version->configure(-text => $v);
					reconfigure_engine();
					refresh();
					}

			);
 	}
}
sub track_gui { 
	$debug2 and print "&track_gui\n";
	@_ = discard_object(@_);
	my $n = shift;
	return if $ti{$n}->hide;
	
	$debug and print "found index: $n\n";
	my @rw_items = @_ ? @_ : (
			[ 'command' => "REC",
				-foreground => 'red',
				-command  => sub { 
					return if eval_iam("engine-status") eq 'running';
					$ti{$n}->set(rw => "REC");
					
					refresh_track($n);
					refresh_group();
					reconfigure_engine();
			}],
			[ 'command' => "MON",
				-command  => sub { 
					return if eval_iam("engine-status") eq 'running';
					$ti{$n}->set(rw => "MON");
					refresh_track($n);
					refresh_group();
					reconfigure_engine();
			}],
			[ 'command' => "OFF", 
				-command  => sub { 
					return if eval_iam("engine-status") eq 'running';
					$ti{$n}->set(rw => "OFF");
					refresh_track($n);
					refresh_group();
					reconfigure_engine();
			}],
		);
	my ($number, $name, $version, $rw, $ch_r, $ch_m, $vol, $mute, $solo, $unity, $pan, $center);
	$number = $track_frame->Label(-text => $n,
									-justify => 'left');
	my $stub = " ";
	$stub .= $ti{$n}->active;
	$name = $track_frame->Label(
			-text => $ti{$n}->name,
			-justify => 'left');
	$version = $track_frame->Menubutton( 
					-text => $stub,
					# -relief => 'sunken',
					-tearoff => 0);
	my @versions = '';
	#push @versions, @{$ti{$n}->versions} if @{$ti{$n}->versions};
	my $ref = ref $ti{$n}->versions ;
		$ref =~ /ARRAY/ and 
		push (@versions, @{$ti{$n}->versions}) or
		croak "chain $n, found unexpectedly $ref\n";;
	my $indicator;
	for my $v (@versions) {
					$version->radiobutton(
						-label => $v,
						-value => $v,
						-variable => \$indicator,
						-command => 
		sub { 
			$ti{$n}->set( active => $v );
			return if $ti{$n}->rec_status eq "REC";
			$version->configure( -text=> $ti{$n}->current_version );
			reconfigure_engine();
			}
					);
	}

	$ch_r = $track_frame->Menubutton(
					# -relief => 'groove',
					-tearoff => 0,
				);
	my @range;
	push @range, 1..$soundcard_channels if $n > 2; # exclude Master/Mixdown
	
	for my $v (@range) {
		$ch_r->radiobutton(
			-label => $v,
			-value => $v,
			-command => sub { 
				return if eval_iam("engine-status") eq 'running';
			#	$ti{$n}->set(rw => 'REC');
				$ti{$n}->source($v);
				refresh_track($n) }
			)
	}
	@range = ();

	push @range, "off" if $n > 2;
	push @range, 1..$soundcard_channels if $n != 2; # exclude Mixdown

	$ch_m = $track_frame->Menubutton(
					-tearoff => 0,
					# -relief => 'groove',
				);
				for my $v (@range) {
					$ch_m->radiobutton(
						-label => $v,
						-value => $v,
						-command => sub { 
							return if eval_iam("engine-status") eq 'running';
							$ti{$n}->set_send($v);
							refresh_track($n);
							reconfigure_engine();
 						}
				 		)
				}
	$rw = $track_frame->Menubutton(
		-text => $ti{$n}->rw,
		-tearoff => 0,
		# -relief => 'groove',
	);
	map{$rw->AddItems($_)} @rw_items; 

 
	my $p_num = 0; # needed when using parameter controllers
	# Volume
	
	if ( need_vol_pan($ti{$n}->name, "vol") ){

		my $vol_id = $ti{$n}->vol;

		local $debug = 0;


		$debug and print "vol cop_id: $vol_id\n";
		my %p = ( 	parent => \$track_frame,
				chain  => $n,
				type => 'ea',
				cop_id => $vol_id,
				p_num		=> $p_num,
				length => 300, 
				);


		 $debug and do {my %q = %p; delete $q{parent}; print
		 "=============\n%p\n",yaml_out(\%q)};

		$vol = make_scale ( \%p );
		# Mute

		$mute = $track_frame->Button(
			-command => sub { 
				if ($copp{$vol_id}->[0] != $mute_level{$cops{$vol_id}->{type}} and
					$copp{$vol_id}->[0] != $fade_out_level{$cops{$vol_id}->{type}}
				) {  # non-zero volume
					$ti{$n}->mute;
					$mute->configure(-background => $namapalette{Mute});
				}
				else {
					$ti{$n}->unmute;
					$mute->configure(-background => $off);
				}
			}	
		  );

		# Unity

		$unity = $track_frame->Button(
				-command => sub { 
					effect_update_copp_set(
						$vol_id, 
						0, 
						$unity_level{$cops{$vol_id}->{type}});
				}
		  );
	} else {

		$vol = $track_frame->Label;
		$mute = $track_frame->Label;
		$unity = $track_frame->Label;

	}

	if ( need_vol_pan($ti{$n}->name, "pan") ){
	  
		# Pan
		
		my $pan_id = $ti{$n}->pan;
		
		$debug and print "pan cop_id: $pan_id\n";
		$p_num = 0;           # first parameter
		my %q = ( 	parent => \$track_frame,
				chain  => $n,
				type => 'epp',
				cop_id => $pan_id,
				p_num		=> $p_num,
				);
		# $debug and do { my %q = %p; delete $q{parent}; print "x=============\n%p\n",yaml_out(\%q) };
		$pan = make_scale ( \%q );

		# Center

		$center = $track_frame->Button(
			-command => sub { 
				effect_update_copp_set($pan_id, 0, 50);
			}
		  );
	} else { 

		$pan = $track_frame->Label;
		$center = $track_frame->Label;
	}
	
	my $effects = $effect_frame->Frame->pack(-fill => 'both');;

	# effects, held by track_widget->n->effects is the frame for
	# all effects of the track

	@{ $track_widget{$n} }{qw(name version rw ch_r ch_m mute effects)} 
		= ($name,  $version, $rw, $ch_r, $ch_m, $mute, \$effects);#a ref to the object
	#$debug and print "=============\n\%track_widget\n",yaml_out(\%track_widget);
	my $independent_effects_frame 
		= ${ $track_widget{$n}->{effects} }->Frame->pack(-fill => 'x');


	my $controllers_frame 
		= ${ $track_widget{$n}->{effects} }->Frame->pack(-fill => 'x');
	
	# parents are the independent effects
	# children are controllers for various paramters

	$track_widget{$n}->{parents} = $independent_effects_frame;

	$track_widget{$n}->{children} = $controllers_frame;
	
	$independent_effects_frame
		->Label(-text => uc $ti{$n}->name )->pack(-side => 'left');

	#$debug and print( "Number: $n\n"),MainLoop if $n == 2;
	my @tags = qw( EF P1 P2 L1 L2 L3 L4 );
	my @starts =   ( $e_bound{cop}{a}, 
					 $e_bound{preset}{a}, 
					 $e_bound{preset}{b}, 
					 $e_bound{ladspa}{a}, 
					 $e_bound{ladspa}{b}, 
					 $e_bound{ladspa}{c}, 
					 $e_bound{ladspa}{d}, 
					);
	my @ends   =   ( $e_bound{cop}{z}, 
					 $e_bound{preset}{b}, 
					 $e_bound{preset}{z}, 
					 $e_bound{ladspa}{b}-1, 
					 $e_bound{ladspa}{c}-1, 
					 $e_bound{ladspa}{d}-1, 
					 $e_bound{ladspa}{z}, 
					);
	my @add_effect;

	map{push @add_effect, effect_button($n, shift @tags, shift @starts, shift @ends)} 1..@tags;
	
	$number->grid($name, $version, $rw, $ch_r, $ch_m, $vol, $mute, $unity, $pan, $center, @add_effect);

	$track_widget_remove{$n} = [
		grep{ $_ } (
			$number, 
			$name, 
			$version, 
			$rw, 
			$ch_r, 
			$ch_m, 
			$vol,
			$mute, 
			$unity, 
			$pan, 
			$center, 
			@add_effect,
			$effects,
		)
	];

	refresh_track($n);

}

sub remove_track_gui {
 	@_ = discard_object( @_ );
 	my $n = shift;
	$debug2 and say "&remove_track_gui";
	return unless $track_widget_remove{$n};
 	map {$_->destroy  } @{ $track_widget_remove{$n} };
	delete $track_widget_remove{$n};
	delete $track_widget{$n};
}

sub paint_mute_buttons {
	map{ $track_widget{$_}{mute}->configure(
			-background 		=> $namapalette{Mute},

			)} grep { $ti{$_}->old_vol_level}# muted tracks
				map { $_->n } Audio::Nama::Track::all;  # track numbers
}

sub create_master_and_mix_tracks { 
	$debug2 and print "&create_master_and_mix_tracks\n";


	my @rw_items = (
			[ 'command' => "MON",
				-command  => sub { 
						return if eval_iam("engine-status") eq 'running';
						$tn{Master}->set(rw => "MON");
						refresh_track($tn{Master}->n);
			}],
			[ 'command' => "OFF", 
				-command  => sub { 
						return if eval_iam("engine-status") eq 'running';
						$tn{Master}->set(rw => "OFF");
						refresh_track($tn{Master}->n);
			}],
		);

	track_gui( $tn{Master}->n, @rw_items );

	track_gui( $tn{Mixdown}->n); 

	group_gui('Main');
}

sub update_version_button {
	@_ = discard_object(@_);
	my ($n, $v) = @_;
	carp ("no version provided \n") if ! $v;
	my $w = $track_widget{$n}->{version};
					$w->radiobutton(
						-label => $v,
						-value => $v,
						-command => 
		sub { $track_widget{$n}->{version}->configure(-text=>$v) 
				unless $ti{$n}->rec_status eq "REC" }
					);
}

sub add_effect_gui {
		$debug2 and print "&add_effect_gui\n";
		@_ = discard_object(@_);
		my %p 			= %{shift()};
		my ($n,$code,$id,$parent_id,$parameter) =
			@p{qw(chain type cop_id parent_id parameter)};
		my $i = $effect_i{$code};

		$debug and print yaml_out(\%p);

		$debug and print "cop_id: $id, parent_id: $parent_id\n";
		# $id is determined by cop_add, which will return the
		# existing cop_id if supplied

		# check display format, may be 'scale' 'field' or 'hidden'
		
		my $display_type = $cops{$id}->{display}; # individual setting
		defined $display_type or $display_type = $effects[$i]->{display}; # template
		$debug and print "display type: $display_type\n";

		return if $display_type eq q(hidden);

		my $frame ;
		if ( ! $parent_id ){ # independent effect
			$frame = $track_widget{$n}->{parents}->Frame->pack(
				-side => 'left', 
				-anchor => 'nw',)
		} else {                 # controller
			$frame = $track_widget{$n}->{children}->Frame->pack(
				-side => 'top', 
				-anchor => 'nw')
		}

		$effects_widget{$id} = $frame; 
		# we need a separate frame so title can be long

		# here add menu items for Add Controller, and Remove

		my $parentage = $effects[ $effect_i{ $cops{$parent_id}->{type}} ]
			->{name};
		$parentage and $parentage .=  " - ";
		$debug and print "parentage: $parentage\n";
		my $eff = $frame->Menubutton(
			-text => $parentage. $effects[$i]->{name}, -tearoff => 0,);

		$eff->AddItems([
			'command' => "Remove",
			-command => sub { remove_effect($id) }
		]);
		$eff->grid();
		my @labels;
		my @sliders;

		# make widgets

		for my $p (0..$effects[$i]->{count} - 1 ) {
		my @items;
		#$debug and print "p_first: $p_first, p_last: $p_last\n";
		for my $j ($e_bound{ctrl}{a}..$e_bound{ctrl}{z}) {   
			push @items, 				
				[ 'command' => $effects[$j]->{name},
					-command => sub { add_effect ({
							parent_id => $id,
							chain => $n,
							parameter  => $p,
							type => $effects[$j]->{code} } )  }
				];

		}
		push @labels, $frame->Menubutton(
				-text => $effects[$i]->{params}->[$p]->{name},
				-menuitems => [@items],
				-tearoff => 0,
		);
			$debug and print "parameter name: ",
				$effects[$i]->{params}->[$p]->{name},"\n";
			my $v =  # for argument vector 
			{	parent => \$frame,
				cop_id => $id, 
				p_num  => $p,
			};
			push @sliders,make_scale($v);
		}

		if (@sliders) {

			$sliders[0]->grid(@sliders[1..$#sliders]);
			 $labels[0]->grid(@labels[1..$#labels]);
		}
}


sub project_label_configure{ 
	@_ = discard_object(@_);
	$project_label->configure( @_ ) }

sub length_display{ 
	@_ = discard_object(@_);
	$setup_length->configure(@_)};

sub clock_config { 
	@_ = discard_object(@_);
	$clock->configure( @_ )}

sub manifest { $ew->deiconify() }

sub destroy_widgets {

	map{ $_->destroy } map{ $_->children } $effect_frame;
	#my @children = $group_frame->children;
	#map{ $_->destroy  } @children[1..$#children];
	my @children = $track_frame->children;
	# leave field labels (first row)
	map{ $_->destroy  } @children[11..$#children]; # fragile
	%mark_widget and map{ $_->destroy } values %mark_widget;
}
sub remove_effect_gui { 
	@_ = discard_object(@_);
	$debug2 and print "&remove_effect_gui\n";
	my $id = shift;
	my $n = $cops{$id}->{chain};
	$debug and print "id: $id, chain: $n\n";

	$debug and print "i have widgets for these ids: ", join " ",keys %effects_widget, "\n";
	$debug and print "preparing to destroy: $id\n";
	return unless defined $effects_widget{$id};
	$effects_widget{$id}->destroy();
	delete $effects_widget{$id}; 

}

sub effect_button {
	local $debug = 0;	
	$debug2 and print "&effect_button\n";
	my ($n, $label, $start, $end) = @_;
	$debug and print "chain $n label $label start $start end $end\n";
	my @items;
	my $widget;
	my @indices = ($start..$end);
	if ($start >= $e_bound{ladspa}{a} and $start <= $e_bound{ladspa}{z}){
		@indices = ();
		@indices = @ladspa_sorted[$start..$end];
		$debug and print "length sorted indices list: ".scalar @indices. "\n";
	$debug and print "Indices: @indices\n";
	}
		
		for my $j (@indices) { 
		push @items, 				
			[ 'command' => "$effects[$j]->{count} $effects[$j]->{name}" ,
				-command  => sub { 
					 add_effect( {chain => $n, type => $effects[$j]->{code} } ); 
					$ew->deiconify; # display effects window
					} 
			];
	}
	$widget = $track_frame->Menubutton(
		-text => $label,
		-tearoff =>0,
		# -relief => 'raised',
		-menuitems => [@items],
	);
	$widget;
}

sub make_scale {
	
	$debug2 and print "&make_scale\n";
	my $ref = shift;
	my %p = %{$ref};
# 	%p contains following:
# 	cop_id   => operator id, to access dynamic effect params in %copp
# 	parent => parent widget, i.e. the frame
# 	p_num      => parameter number, starting at 0
# 	length       => length widget # optional 
	my $id = $p{cop_id};
	my $n = $cops{$id}->{chain};
	my $code = $cops{$id}->{type};
	my $p  = $p{p_num};
	my $i  = $effect_i{$code};

	$debug and print "id: $id code: $code\n";
	

	# check display format, may be text-field or hidden,

	$debug and  print "i: $i code: $effects[$i]->{code} display: $effects[$i]->{display}\n";
	my $display_type = $cops{$id}->{display};
	defined $display_type or $display_type = $effects[$i]->{display};
	$debug and print "display type: $display_type\n";
	return if $display_type eq q(hidden);


	$debug and print "to: ", $effects[$i]->{params}->[$p]->{end}, "\n";
	$debug and print "p: $p code: $code\n";
	$debug and print "is_log_scale: ".is_log_scale($i,$p), "\n";

	# set display type to individually specified value if it exists
	# otherwise to the default for the controller class


	
	if 	($display_type eq q(scale) ) { 

		# return scale type controller widgets
		my $frame = ${ $p{parent} }->Frame;
			

		#return ${ $p{parent} }->Scale(
		
		my $log_display;
		
		my $controller = $frame->Scale(
			-variable => \$copp{$id}->[$p],
			-orient => 'horizontal',
			-from   =>  $effects[$i]->{params}->[$p]->{begin},
			-to     =>  $effects[$i]->{params}->[$p]->{end},
			-resolution => resolution($i, $p),
		  -width => 12,
		  -length => $p{length} ? $p{length} : 100,
		  -command => sub { effect_update($id, $p, $copp{$id}->[$p]) }
		  );

		# auxiliary field for logarithmic display
		if ( is_log_scale($i, $p)  )
		#	or $code eq 'ea') 
			{
			my $log_display = $frame->Label(
				-text => exp $effects[$i]->{params}->[$p]->{default},
				-width => 5,
				);
			$controller->configure(
				-variable => \$copp_exp{$id}->[$p],
		  		-command => sub { 
					$copp{$id}->[$p] = exp $copp_exp{$id}->[$p];
					effect_update($id, $p, $copp{$id}->[$p]);
					$log_display->configure(
						-text => 
						$effects[$i]->{params}->[$p]->{name} =~ /hz|frequency/i
							? int $copp{$id}->[$p]
							: dn($copp{$id}->[$p], 1)
						);
					}
				);
		$log_display->grid($controller);
		}
		else { $controller->grid; }

		return $frame;

	}	

	elsif ($display_type eq q(field) ){ 

	 	# then return field type controller widget

		return ${ $p{parent} }->Entry(
			-textvariable =>\$copp{$id}->[$p],
			-width => 6,
	#		-command => sub { effect_update($id, $p, $copp{$id}->[$p]) },
			# doesn't work with Entry widget
			);	

	}
	else { croak "missing or unexpected display type: $display_type" }

}

sub is_log_scale {
	my ($i, $p) = @_;
	$effects[$i]->{params}->[$p]->{hint} =~ /logarithm/ 
}
sub resolution {
	my ($i, $p) = @_;
	my $res = $effects[$i]->{params}->[$p]->{resolution};
	return $res if $res;
	my $end = $effects[$i]->{params}->[$p]->{end};
	my $beg = $effects[$i]->{params}->[$p]->{begin};
	return 1 if abs($end - $beg) > 30;
	return abs($end - $beg)/100
}

sub arm_mark_toggle { 
	if ($markers_armed) {
		$markers_armed = 0;
		$mark_remove->configure( -background => $off);
	}
	else{
		$markers_armed = 1;
		$mark_remove->configure( -background => $namapalette{MarkArmed});
	}
}
sub marker {
	@_ = discard_object( @_); # UI
	my $mark = shift; # Mark
	#print "mark is ", ref $mark, $/;
	my $pos = $mark->time;
	#print $pos, " ", int $pos, $/;
		$mark_widget{$pos} = $mark_frame->Button( 
			-text => (join " ",  colonize( int $pos ), $mark->name),
			-background => $off,
			-command => sub { mark($mark) },
		)->pack(-side => 'left');
}

sub restore_time_marks {
	@_ = discard_object( @_);
# 	map {$_->dumpp} Audio::Nama::Mark::all(); 
#	Audio::Nama::Mark::all() and 
	map{ $ui->marker($_) } Audio::Nama::Mark::all() ; 
	$time_step->configure( -text => $unit == 1 ? q(Sec) : q(Min) )
}
sub destroy_marker {
	@_ = discard_object( @_);
	my $pos = shift;
	$mark_widget{$pos}->destroy; 
}


sub get_saved_colors {
	$debug2 and print "&get_saved_colors\n";

	# aliases
	
	*old_bg = \$palette{mw}{background};
	*old_abg = \$palette{mw}{activeBackground};
	$old_bg = '#d915cc1bc3cf' unless $old_bg;
	#print "pb: $palette{mw}{background}\n";


	my $pal = join_path($project_root, $palette_file);
	-f $pal or $pal = $default_palette_yml;
	assign_var( $pal, qw[%palette %namapalette]);
	
	*rec = \$namapalette{RecBackground};
	*mon = \$namapalette{MonBackground};
	*off = \$namapalette{OffBackground};

	$old_abg = $palette{mw}{activeBackground};
	$old_abg = $project_label->cget('-activebackground') unless $old_abg;
	#print "1palette: \n", yaml_out( \%palette );
	#print "\n1namapalette: \n", yaml_out(\%namapalette);
	my %setformat;
	map{ $setformat{$_} = $palette{mw}{$_} if $palette{mw}{$_}  } 
		keys %{$palette{mw}};	
	#print "\nsetformat: \n", yaml_out(\%setformat);
	$mw->setPalette( %setformat );
}
sub colorset {
	my ($widgetid, $field) = @_;
	sub { 
			my $widget = eval "\$$widgetid";
			#print "ancestor: $widgetid\n";
			my $new_color = colorchooser($field,$widget->cget("-$field"));
			if( defined $new_color ){
				
				# install color in palette listing
				$palette{$widgetid}{$field} = $new_color;

				# set the color
				my @fields =  ($field => $new_color);
				push (@fields, 'background', $widget->cget('-background'))
					unless $field eq 'background';
				#print "fields: @fields\n";
				$widget->setPalette( @fields );
			}
 	};
}

sub namaset {
	my ($field) = @_;
	sub { 	
			#print "f: $field np: $namapalette{$field}\n";
			my $color = colorchooser($field,$namapalette{$field});
			if ($color){ 
				# install color in palette listing
				$namapalette{$field} = $color;

				# set those objects who are not
				# handled by refresh
	*rec = \$namapalette{RecBackground};
	*mon = \$namapalette{MonBackground};
	*off = \$namapalette{OffBackground};

				$clock->configure(
					-background => $namapalette{ClockBackground},
					-foreground => $namapalette{ClockForeground},
				);
				$group_label->configure(
					-background => $namapalette{GroupBackground},
					-foreground => $namapalette{GroupForeground},
				);
				refresh();
			}
	}

}

sub colorchooser { 
	#print "colorchooser\n";
	#my $debug = 1;
	my ($field, $initialcolor) = @_;
	$debug and print "field: $field, initial color: $initialcolor\n";
	my $new_color = $mw->chooseColor(
							-title => $field,
							-initialcolor => $initialcolor,
							);
	#print "new color: $new_color\n";
	$new_color;
}
sub init_palettefields {
	@palettefields = qw[ 
		foreground
		background
		activeForeground
		activeBackground
		selectForeground
		selectBackground
		selectColor
		highlightColor
		highlightBackground
		disabledForeground
		insertBackground
		troughColor
	];

	@namafields = qw [
		RecForeground
		RecBackground
		MonForeground
		MonBackground
		OffForeground
		OffBackground
		ClockForeground
		ClockBackground
		Capture
		Play
		Mixdown
		GroupForeground
		GroupBackground
		SendForeground
		SendBackground
		SourceForeground
		SourceBackground
		Mute
		MarkArmed
	];
}

sub save_palette {
 	serialize (
 		file => join_path(project_root(), $palette_file),
		format => 'yaml',
 		vars => [ qw( %palette %namapalette ) ],
 		class => 'Audio::Nama')
}

### end
 # root namespace!

## refresh functions

sub set_widget_color {
	my ($widget, $status) = @_;
	my %rw_foreground = (	REC  => $namapalette{RecForeground},
						 	MON => $namapalette{MonForeground},
						 	OFF => $namapalette{OffForeground},
						);

	my %rw_background =  (	REC  => $rec,
							MON  => $mon,
							OFF  => $off );
		
#	print "namapalette:\n",yaml_out( \%namapalette);
#	print "rec: $rec, mon: $mon, off: $off\n";

	$widget->configure( -background => $rw_background{$status} );
	$widget->configure( -foreground => $rw_foreground{$status} );
}


	
sub refresh_group { 
	# main group, in this case we want to skip null group
	$debug2 and print "&refresh_group\n";
	
	
		my $status;
		if ( 	grep{ $_->rec_status eq 'REC'} 
				map{ $tn{$_} }
				$main->tracks ){

			$status = 'REC'

		}elsif(	grep{ $_->rec_status eq 'MON'} 
				map{ $tn{$_} }
				$main->tracks ){

			$status = 'MON'

		}else{ 
		
			$status = 'OFF' }

$debug and print "group status: $status\n";

	set_widget_color($group_rw, $status); 



	croak "some crazy status |$status|\n" if $status !~ m/rec|mon|off/i;
		#$debug and print "attempting to set $status color: ", $take_color{$status},"\n";

	set_widget_color( $group_rw, $status) if $group_rw;
}
sub refresh_track {
	
	@_ = discard_object(@_);
	my $n = shift;
	$debug2 and print "&refresh_track\n";
	
	my $rec_status = $ti{$n}->rec_status;
	$debug and print "track: $n rec_status: $rec_status\n";

	return unless $track_widget{$n}; # hidden track
	
	# set the text for displayed fields

	$track_widget{$n}->{rw}->configure(-text => $rec_status);
	$track_widget{$n}->{ch_r}->configure( -text => 
				$n > 2
					? $ti{$n}->source
					:  q() );
	$track_widget{$n}->{ch_m}->configure( -text => $ti{$n}->send);
	$track_widget{$n}->{version}->configure(-text => $ti{$n}->current_version || "");
	
	map{ set_widget_color( 	$track_widget{$n}->{$_}, 
							$rec_status)
	} qw(name rw );
	
	set_widget_color( 	$track_widget{$n}->{ch_r},
				
 							($rec_status eq 'REC'
								and $n > 2 )
 								? 'REC'
 								: 'OFF');
	
	set_widget_color( $track_widget{$n}->{ch_m},
							$rec_status eq 'OFF' 
								? 'OFF'
								: $ti{$n}->send 
									? 'MON'
									: 'OFF');
}

sub refresh {  
	remove_small_wavs();
 	$ui->refresh_group(); 
	#map{ $ui->refresh_track($_) } map{$_->n} grep{!  $_->hide} Audio::Nama::Track::all();
	#map{ $ui->refresh_track($_) } grep{$remove_track_widget{$_} map{$_->n}  Audio::Nama::Track::all();
	map{ $ui->refresh_track($_) } map{$_->n}  Audio::Nama::Track::all();
}
sub refresh_oids{ # OUTPUT buttons
	map{ $widget_o{$_}->configure( # uses hash
			-background => 
				$oid_status{$_} ?  'AntiqueWhite' : $old_bg,
			-activebackground => 
				$oid_status{$_} ? 'AntiqueWhite' : $old_bg
			) } keys %widget_o;
}

### end


## The following code loads the object core of the system 
## and initiates the chain templates (rules)

package Audio::Nama::Graphical;  ## gui routines

our @ISA = 'Audio::Nama';      ## default to root class

## The following methods belong to the Graphical interface class

sub hello {"make a window";}
sub loop {
	package Audio::Nama;
	$attribs->{already_prompted} = 0;
	$term->tkRunning(1);
  	while (1) {
  		my ($user_input) = $term->readline($prompt) ;
  		Audio::Nama::process_line( $user_input );
  	}
}

## The following methods belong to the Text interface class

package Audio::Nama::Text;
our @ISA = 'Audio::Nama';
use Carp;
use Audio::Nama::Assign qw(:all);

sub hello {"hello world!";}

sub loop {
	package Audio::Nama;
	issue_first_prompt();
	$Event::DIED = sub {
	   my ($event, $errmsg) = @_;
	   say $errmsg;
	   $attribs->{line_buffer} = q();
	   $term->clear_message();
	   $term->rl_reset_line_state();
	};
	Event::loop();
}

sub show_versions {
		if (@{$this_track->versions} ){
			my $cache_map = $this_track->cache_map;
			"All versions: ". join(" ", 
				map { $_ . ( $cache_map->{$_} and 'c') } @{$this_track->versions}
			). $/
		} 
}


sub show_send { "Send: ". $this_track->send_id. $/ 
					if $this_track->rec_status ne 'OFF'
						and $this_track->send_id
}

sub show_bus { "Bus: ". $this_track->group. $/ if $this_track->group ne 'Main' }

sub show_effects {
	Audio::Nama::sync_effect_parameters();
	my @lines;
 	map { 
 		my $op_id = $_;
		my @params;
 		 my $i = $effect_i{ $cops{ $op_id }->{type} };
 		 push @lines, $op_id. ": " . $effects[ $i ]->{name}.  "\n";
 		 my @pnames = @{$effects[ $i ]->{params}};
			map{ push @lines,
			 	"    ".($_+1).q(. ) . $pnames[$_]->{name} . ": ".  $copp{$op_id}->[$_] . "\n";
		 	} (0..scalar @pnames - 1);
			map{ push @lines,
			 	"    ".($_+1).": ".  $copp{$op_id}->[$_] . "\n";
		 	} (scalar @pnames .. (scalar @{$copp{$op_id}} - 1)  )
				if scalar @{$copp{$op_id}} - scalar @pnames - 1; 
			#push @lines, join("; ", @params) . "\n";
 
 	} @{ $this_track->ops };

	my $i = $this_track->inserts;

	# display if there is actually something there

	if ($i->{insert_type}){ push @lines, yaml_out($i) }
		
	join "", @lines;
 	
}
sub show_modifiers {
	join "", "Modifiers: ",$this_track->modifiers, $/
		if $this_track->modifiers;
}
sub show_effect_chain_stack {
		return "Bypassed effect chains: "
				.scalar @{ $this_track->effect_chain_stack }.$/
			if @{ $this_track->effect_chain_stack } ;
		undef;
}
	
sub show_region {
	my @lines;
	push @lines, "Start at: ",
		$this_track->playat, $/ if $this_track->playat;
	push @lines, "Region start: ", $this_track->region_start, $/
		if $this_track->region_start;
	push @lines, "Region end: ", $this_track->region_end, $/
		if $this_track->region_end;
	return(join "", @lines);
}

sub show_status {
	my @fields;
	push @fields, $main->rw eq 'REC' 
					? "live input allowed" 
					: "live input disabled";
	push @fields, "record" if grep{ ! /Mixdown/ } Audio::Nama::really_recording();
	push @fields, "playback" if grep { $_->rec_status eq 'MON' } 
		map{ $tn{$_} } $main->tracks, q(Mixdown);
	push @fields, "mixdown" 
		if $tn{Mixdown}->rec_status eq 'REC';
	push @fields, "doodle" if $preview eq 'doodle';
	push @fields, "preview" if $preview eq 'preview';
	push @fields, "master" if $mastering_mode;
	"[ ". join(", ", @fields) . " ]\n";
}
sub placeholder { 
	my $val = shift;
	return $val if defined $val;
	$use_placeholders ? q(--) : q() 
}

sub show_inserts {
	my $output;
	$output = $Audio::Nama::Insert::by_index{$this_track->prefader_insert}->dump
		if $this_track->prefader_insert;
	$output .= $Audio::Nama::Insert::by_index{$this_track->postfader_insert}->dump
		if $this_track->postfader_insert;
	"Inserts:\n".join( "\n",map{" "x4 . $_ } split("\n",$output))."\n" if $output;
}

{
my $format_top = <<TOP;
Track Name      Ver. Setting Status      Source       Bus         Vol  Pan
=============================================================================
TOP

my $format_picture = <<PICTURE;
@>>   @<<<<<<<<< @>    @<<    @||||  @|||||||||||||   @<<<<<<<<<  @>>  @>> 
PICTURE

sub show_tracks {
    no warnings;
	$^A = $format_top;
    my @tracks = @_;
    map {   formline $format_picture, 
            $_->n,
            $_->name,
            placeholder( $_->current_version || undef ),
			lc $_->rw,
            $_->rec_status_display,
			placeholder($_->source_status),
			placeholder($_->group),
			placeholder($copp{$_->vol}->[0]),
			placeholder($copp{$_->pan}->[0]),
        } grep{ ! $_-> hide} @tracks;
        
	my $output = $^A;
	$^A = "";
	#$output .= show_tracks_extra_info();
	$output;
}

}

sub show_tracks_extra_info {

	my $string;
	$string .= $/. "Global version setting: ".  $Audio::Nama::main->version. $/
		if $Audio::Nama::main->version;
	$string .=  $/. Audio::Nama::Text::show_status();
	$string .=  $/;	
	$string;
}


format STDOUT_TOP =
Track Name      Ver. Setting  Status   Source           Send        Vol  Pan 
=============================================================================
.
format STDOUT =
@>>   @<<<<<<<<< @>    @<<     @<< @|||||||||||||| @||||||||||||||  @>>  @>> ~~
splice @format_fields, 0, 9
.

sub helpline {
	my $cmd = shift;
	my $text = "Command: $cmd\n";
	$text .=  "Shortcuts: $commands{$cmd}->{short}\n"
			if $commands{$cmd}->{short};	
	$text .=  "Description: $commands{$cmd}->{what}\n";
	$text .=  "Usage: $cmd "; 

	if ( $commands{$cmd}->{parameters} 
			&& $commands{$cmd}->{parameters} ne 'none' ){
		$text .=  $commands{$cmd}->{parameters}
	}
	$text .= "\n";
	my $example = $commands{$cmd}->{example};
	$example =~ s/!n/\n/g;
	$text .=  "Example: $example\n" if $example;
	($/, ucfirst $text, $/);
	
}
sub helptopic {
	my $index = shift;
	$index =~ /^(\d+)$/ and $index = $help_topic[$index];
	my @output;
	push @output, "\n-- ", ucfirst $index, " --\n\n";
	push @output, $help_topic{$index}, $/;
	@output;
}

sub help { 
	my $name = shift;
	chomp $name;
	#print "seeking help for argument: $name\n";
	$iam_cmd{$name} and print <<IAM;

$name is an Ecasound command.  See 'man ecasound-iam'.
IAM
	my @output;
	if ( $help_topic{$name}){
		@output = helptopic($name);
	} elsif ($name !~ /\D/ and $name == 0){
		@output = map{ helptopic $_ } @help_topic;
	} elsif ( $name =~ /^(\d+)$/ and $1 < 20  ){
		@output = helptopic($name)
	} else {
		my %helped = (); 
		my @help = ();
		if ( $commands{$name} ){
			push @help, helpline($name);
			$helped{$name}++
		}
		map{  
			my $cmd = $_ ;
			if ($cmd =~ /$name/ ){
				push @help, helpline($cmd) unless $helped{$cmd}; 
				$helped{$cmd}++ ;
			}
			if ( ! $helped{$cmd} and
					grep{ /$name/ } split " ", $commands{$cmd}->{short} ){
				push @help, helpline($cmd) 
			}
		} keys %commands;
		if ( @help ){ push @output, 
			qq("$name" matches the following commands:\n\n), @help;
		}
	}
	if (@output){
		Audio::Nama::pager( @output ); 
	} else { print "$name: no help found.\n"; }
	
}
sub help_effect {
	my $input = shift;
	print "input: $input\n";
	# e.g. help tap_reverb    
	#      help 2142
	#      help var_chipmunk # preset


	if ($input !~ /\D/){ # all digits
		$input = $ladspa_label{$input}
			or print("$input: effect not found.\n\n"), return;
	}
	elsif ( my $id = $ladspa_unique_id{$input} ){$input = $ladspa_label{$id} }
	if ( $effect_i{$input} ) {} # do nothing
	elsif ( $effect_j{$input} ) { $input = $effect_j{$input} }
	else { print("$input: effect not found.\n\n"), return }
	if ($input =~ /pn:/) {
		print grep{ /$input/  } @effects_help;
	}
	elsif ( $input =~ /el:/) {
	
	my @output = $ladspa_help{$input};
	print "label: $input\n";
	Audio::Nama::pager( @output );
	#print $ladspa_help{$input};
	} else { 
	print "$input: Ecasound effect. Type 'man ecasound' for details.\n";
	}
}


sub find_effect {
	my @keys = @_;
	#print "keys: @keys\n";
	#my @output;
	my @matches = grep{ 
		my $help = $_; 
		my $didnt_match;
		map{ $help =~ /\Q$_\E/i or $didnt_match++ }  @keys;
		! $didnt_match; # select if no cases of non-matching
	} @effects_help;
	if ( @matches ){
# 		push @output, <<EFFECT;
# 
# Effects matching "@keys" were found. The "pn:" prefix 
# indicates an Ecasound preset. The "el:" prefix indicates
# a LADSPA plugin. No prefix indicates an Ecasound chain
# operator.
# 
# EFFECT
	Audio::Nama::pager( $text_wrap->paragraphs(@matches) , "\n" );
	} else { print "No matching effects.\n\n" }
}


sub t_load_project {
	package Audio::Nama;
	return if engine_running() and really_recording();
	my $name = shift;
	print "input name: $name\n";
	my $newname = remove_spaces($name);
	$newname =~ s(/$)(); # remove trailing slash
	print ("Project $newname does not exist\n"), return
		unless -d join_path project_root(), $newname; 
	stop_transport();
	load_project( name => $newname );
	print "loaded project: $project_name\n";
	$debug and print "hook: $Audio::Nama::execute_on_project_load\n";
	Audio::Nama::command_process($Audio::Nama::execute_on_project_load);
		
	
}

    
sub t_create_project {
	package Audio::Nama;
	my $name = shift;
	load_project( 
		name => remove_spaces($name),
		create => 1,
	);
	print "created project: $project_name\n";

}
sub t_add_ctrl {
	package Audio::Nama;
	my ($parent, $code, $values) = @_;
	if ( $effect_i{$code} ) {} # do nothing
	elsif ( $effect_j{$code} ) { $code = $effect_j{$code} }
	else { warn "effect code not found: $code\n"; return }
	$debug and print "code: ", $code, $/;
		my %p = (
				chain => $cops{$parent}->{chain},
				parent_id => $parent,
				values => $values,
				type => $code,
			);
		add_effect( \%p );
}

sub t_insert_effect {
	package Audio::Nama;
	my ($before, $code, $values) = @_;
	$code = effect_code( $code );	
	my $running = engine_running();
	print ("Cannot insert effect while engine is recording.\n"), return 
		if $running and Audio::Nama::really_recording;
	print ("Cannot insert effect before controller.\n"), return 
		if $cops{$before}->{belongs_to};

	if ($running){
		$ui->stop_heartbeat;
		Audio::Nama::mute();
		eval_iam('stop');
		sleeper( 0.05);
	}
	my $n = $cops{ $before }->{chain} or 
		print(qq[Insertion point "$before" does not exist.  Skipping.\n]), 
		return;
	
	my $track = $ti{$n};
	$debug and print $track->name, $/;
	#$debug and print join " ",@{$track->ops}, $/; 

	# find offset 
	
	my $offset = 0;
	for my $id ( @{$track->ops} ){
		last if $id eq $before;
		$offset++;
	}

	# remove ops after insertion point if engine is connected
	# note that this will _not_ change the $track->ops list 

	my @ops = @{$track->ops}[$offset..$#{$track->ops}];
	$debug and print "ops to remove and re-apply: @ops\n";
	my $connected = eval_iam('cs-connected');
	if ( $connected ){  
		map{ remove_op($_)} reverse @ops; # reverse order for correct index
	}

	Audio::Nama::Text::t_add_effect( $track, $code, $values );

	$debug and print join " ",@{$track->ops}, $/; 

	# the new op_id is added to the end of the $track->ops list
	# so we need to move it to specified insertion point

	my $op = pop @{$track->ops}; 

	# the above acts directly on $track, because ->ops returns 
	# a reference to the array

	# insert the effect id 
	splice 	@{$track->ops}, $offset, 0, $op;

	$debug and print join " ",@{$track->ops}, $/; 

	# replace the ops that had been removed
	if ($connected ){  
		map{ apply_op($_, $n) } @ops;
	}
		
	if ($running){
		eval_iam('start');	
		sleeper(0.3);
		Audio::Nama::unmute();
		$ui->start_heartbeat;
	}
	$op
}
sub t_add_effect {
	package Audio::Nama;
	my ($track, $code, $values)  = @_;
	$code = effect_code( $code );	
	$debug and print "code: ", $code, $/;
		my %p = (
			chain => $track->n,
			values => $values,
			type => $code,
			);
			#print "adding effect\n";
			$debug and print (yaml_out(\%p));
		add_effect( \%p );
}
sub mixdown {
	print "Enabling mixdown to file.\n";
	$tn{Mixdown}->set(rw => 'REC'); 
	$main->set(rw => 'MON') if $main->rw eq 'OFF';
	$main_out = 0; # no audio output
}
sub mixplay { 
	print "Setting mixdown playback mode.\n";
	$tn{Mixdown}->set(rw => 'MON');
	$main->set(rw => 'OFF');
	$main_out = 1;
}
sub mixoff { 
	print "Leaving mixdown mode.\n";
	$tn{Mixdown}->set(rw => 'OFF');
	$main_out = 1;
	$main->set(rw => 'MON') if $main->rw eq 'OFF';
}
sub bunch {
	package Audio::Nama;
	my ($bunchname, @tracks) = @_;
	if (! $bunchname){
		Audio::Nama::pager(yaml_out( \%bunch ));
	} elsif (! @tracks){
		$bunch{$bunchname} 
			and print "bunch $bunchname: @{$bunch{$bunchname}}\n" 
			or  print "bunch $bunchname: does not exist.\n";
	} elsif (my @mispelled = grep { ! $tn{$_} and ! $ti{$_}} @tracks){
		print "@mispelled: mispelled track(s), skipping.\n";
	} else {
	$bunch{$bunchname} = [ @tracks ];
	}
}
sub add_to_bunch {}


## NO-OP GRAPHIC METHODS 

no warnings qw(redefine);
sub init_gui {}
sub transport_gui {}
sub group_gui {}
sub track_gui {}
sub preview_button {}
sub create_master_and_mix_tracks {}
sub time_gui {}
sub refresh {}
sub refresh_group {}
sub refresh_track {}
sub flash_ready {}
sub update_master_version_button {}
sub update_version_button {}
sub paint_button {}
sub refresh_oids {}
sub project_label_configure{}
sub length_display{}
sub clock_display {}
sub clock_config {}
sub manifest {}
sub global_version_buttons {}
sub destroy_widgets {}
sub destroy_marker {}
sub restore_time_marks {}
sub show_unit {}
sub add_effect_gui {}
sub remove_effect_gui {}
sub marker {}
sub init_palette {}
sub save_palette {}
sub paint_mute_buttons {}
sub remove_track_gui {}
sub reset_engine_mode_color_display {}
sub set_engine_mode_color_display {}

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
  short: set
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
  parameters: <i_soundcard_channel> | 'null' (for metronome) | <s_jack_client_name> | 'jack' (opens ports ecasound:trackname_in_N, connects ports listed in trackname.ports if present in project_root dir)
send:
  type: track
  what: set aux send
  short: out aux m
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
  parameters: none
all:
  type: track
  short: nosolo
  what: unmute tracks after solo
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
  short: show tracks list_tracks lt
  what: show status of all tracks
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
  short: shift
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
  example: loop_enable 1.5 10.0 (loop between 1.5 and 10.0 seconds) !nloop_enable 1 5 (loop between mark indices 1 and 5) !nloop_enable start end (loop between mark ids 'start' and 'end')
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
  example: add_effect amp 6 (LADSPA Simple amp 6dB gain)!nadd_effect var_dali (preset var_dali) Note: no el: or pn: prefix is required
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
  example: modify_effect V 1 -1 (set effect_id V, parameter 1 to -1)!nmodify_effect V 1 - 10 (reduce effect_id V, parameter 1 by 10)!nset multiple effects/parameters: mfx V 1,2,3 + 0.5 ; mfx V,AC,AD 1,2 3.14
remove_effect:
  type: effect
  what: remove effects from selected track
  short: rfx remove_controller rcl
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
  example: asbc jconv
add_send_bus_raw:
  type: bus
  short: asbr
  what: add a send bus that copies all user tracks' raw signals
  parameters: <s_name> <destination>
  example: asbr The_new_bus jconv
add_sub_bus:
  type: bus
  short: asub
  what: add a sub bus (default destination: to mixer via eponymous track)
  parameters: <s_name> [destination: s_track_name|s_jack_client|n_soundcard channel]
  example: asub Strings_bus !nasub Strings_bus some_jack_client
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
change_bus:
  type: bus
  short: cbs
  what: choose the current bus
  parameters: <s_busname>
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
  parameters: none
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
  example: fade in mark1 (fade in default 0.5s starting at mark1)!nfade out mark2 2 (fade out over 2s starting at mark2)!nfade out 2 mark2 (fade out over 2s ending at mark2)!nfade out mark1 mark2 (fade out from mark1 to mark2) 
remove_fade:
  type: effect 
  short: rfd
  what: remove a fade from the current track
  parameters: <i_fade_index1> [<i_fade_index2>...]
list_fade:
  type: effect
  short: lfd
  what: list fades
...

__[grammar]__

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
meta: text semicolon(?) { $Audio::Nama::parser->do_part($item{text}) }
text: /[^;]+/ 
semicolon: ';'
do_part: track_spec command
do_part: track_spec
do_part: command
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
ident: /[-\w]+/   | <error: illegal identifier, word characters only!>	 
marktime: /\d+\.\d+/ 
markname: /\w+/ { 	 
	print("$item[1]}: non-existent mark name. Skipping\n"), return undef 
		unless $Audio::Nama::Mark::by_name{$item[1]};
	$item[1];
}
path: /~?[\w\-\.\/]+/ 
path: shellish
modifier: 'audioloop' | 'select' | 'reverse' | 'playat' | value
end: /[;\s]*$/ 		
help_effect: _help_effect effect end { Audio::Nama::Text::help_effect($item{effect}) ; 1}
find_effect: _find_effect anytag(s) { 
	Audio::Nama::Text::find_effect(@{$item{"anytag(s)"}}); 1}
help: _help 'yml' end { Audio::Nama::pager($Audio::Nama::commands_yml); 1}
help: _help anytag  { Audio::Nama::Text::help($item{anytag}) ; 1}
help: _help end { print $Audio::Nama::help_screen ; 1}
project_name: _project_name end { 
	print "project name: ", $Audio::Nama::project_name, $/; 1}
create_project: _create_project project_id end { 
	Audio::Nama::Text::t_create_project $item{project_id} ; 1}
list_projects: _list_projects end { Audio::Nama::list_projects() ; 1}
load_project: _load_project project_id end {
	Audio::Nama::Text::t_load_project $item{project_id} ; 1}
save_state: _save_state ident end { Audio::Nama::save_state( $item{ident}); 1}
save_state: _save_state end { Audio::Nama::save_state(); 1}
get_state: _get_state ident end {
 	Audio::Nama::load_project( 
 		name => $Audio::Nama::project_name,
 		settings => $item{ident}
 		); 1}
get_state: _get_state end {
 	Audio::Nama::load_project( name => $Audio::Nama::project_name,) ; 1}
getpos: _getpos end {  
	print Audio::Nama::d1( Audio::Nama::eval_iam q(getpos) ), $/; 1}
setpos: _setpos value end {
	Audio::Nama::set_position($item{value}); 1}
forward: _forward value end {
	Audio::Nama::forward( $item{value} ); 1}
rewind: _rewind value end {
	Audio::Nama::rewind( $item{value} ); 1}
to_start: _to_start end { Audio::Nama::to_start(); 1 }
to_end: _to_end end { Audio::Nama::to_end(); 1 }
add_track: _add_track track_name(s) end {
	Audio::Nama::add_track(@{$item{'track_name(s)'}}); 1}
add_tracks: _add_tracks track_name(s) end {
	map{ Audio::Nama::add_track($_)  } @{$item{'track_name(s)'}}; 1}
track_name: ident
set_track: _set_track 'bus' existing_bus_name end {
	$Audio::Nama::this_track->set( group => $item{existing_bus_name}); 1
} 
set_track: _set_track key someval end {
	 $Audio::Nama::this_track->set( $item{key}, $item{someval} ); 1}
dump_track: _dump_track end { Audio::Nama::pager($Audio::Nama::this_track->dump); 1}
dump_group: _dump_group end { Audio::Nama::pager($Audio::Nama::main->dump); 1}
dump_all: _dump_all end { Audio::Nama::dump_all(); 1}
remove_track: _remove_track end { 
	$Audio::Nama::this_track->remove; 
	1;
}
link_track: _link_track track_name target project end {
	Audio::Nama::add_track_alias_project($item{track_name}, $item{target}, $item{project}); 1
}
link_track: _link_track track_name target end {
	Audio::Nama::add_track_alias($item{track_name}, $item{target}); 1
}
target: track_name
project: ident
set_region: _set_region beginning ending end { 
	Audio::Nama::set_region( @item{ qw( beginning ending ) } );
	1;
}
set_region: _set_region beginning end { Audio::Nama::set_region( $item{beginning}, 'END' );
	1;
}
remove_region: _remove_region end { Audio::Nama::remove_region(); 1; }
new_region: _new_region beginning ending track_name(?) end {
	my ($name) = @{$item{'track_name(?)'}};
	Audio::Nama::new_region(@item{qw(beginning ending)}, $name); 1
}
shift_track: _shift_track start_position end {
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
unshift_track: _unshift_track end {
	$Audio::Nama::this_track->set(playat => undef)
}
beginning: marktime | markname
ending: 'END' | marktime | markname 
generate: _generate end { Audio::Nama::generate_setup(); 1}
arm: _arm end { Audio::Nama::arm(); 1}
connect: _connect end { Audio::Nama::connect_transport(); 1}
disconnect: _disconnect end { Audio::Nama::disconnect_transport(); 1}
engine_status: _engine_status end { 
	print(Audio::Nama::eval_iam q(engine-status)); print "\n" ; 1}
start: _start end { Audio::Nama::start_transport(); 1}
stop: _stop end { Audio::Nama::stop_transport(); 1}
ecasound_start: _ecasound_start end { Audio::Nama::eval_iam("stop"); 1}
ecasound_stop: _ecasound_stop  end { Audio::Nama::eval_iam("start"); 1}
show_tracks: _show_tracks end { 	
	Audio::Nama::pager( Audio::Nama::Text::show_tracks ( Audio::Nama::Track::all() ) );
	1;
}
modifiers: _modifiers modifier(s) end {
 	$Audio::Nama::this_track->set(modifiers => (join q(,),
	@{$item{"modifier(s)"}}, q() ));
	1;}
modifiers: _modifiers end { print $Audio::Nama::this_track->modifiers, "\n"; 1}
nomodifiers: _nomodifiers end { $Audio::Nama::this_track->set(modifiers => ""); 1}
show_chain_setup: _show_chain_setup { Audio::Nama::pager($Audio::Nama::chain_setup); 1}
show_io: _show_io { Audio::Nama::show_io(); 1}
show_track: _show_track end {
	my $output = Audio::Nama::Text::show_tracks($Audio::Nama::this_track);
	$output .= Audio::Nama::Text::show_effects();
	$output .= Audio::Nama::Text::show_versions();
	$output .= Audio::Nama::Text::show_send();
	$output .= Audio::Nama::Text::show_bus();
	$output .= Audio::Nama::Text::show_modifiers();
	$output .= join "", "Signal width: ", Audio::Nama::width($Audio::Nama::this_track->width), "\n";
	$output .= Audio::Nama::Text::show_region();
	$output .= Audio::Nama::Text::show_effect_chain_stack();
	$output .= Audio::Nama::Text::show_inserts();
	Audio::Nama::pager( $output );
	1;}
show_track: _show_track track_name end { 
 	Audio::Nama::pager( Audio::Nama::Text::show_tracks( 
	$Audio::Nama::tn{$item{track_name}} )) if $Audio::Nama::tn{$item{track_name}};
	1;}
show_track: _show_track dd end {  
	Audio::Nama::pager( Audio::Nama::Text::show_tracks( $Audio::Nama::ti{$item{dd}} )) if
	$Audio::Nama::ti{$item{dd}};
	1;}
show_mode: _show_mode end { print STDOUT Audio::Nama::Text::show_status; 1}
bus_rec: _bus_rec end {
	$Audio::Nama::Bus::by_name{$Audio::Nama::this_bus}->set(rw => 'REC');
	print "Setting REC-enable for " , $Audio::Nama::this_bus ,
		" bus. You may record user tracks.\n";
	1; }
bus_mon: _bus_mon end {
	$Audio::Nama::Bus::by_name{$Audio::Nama::this_bus}->set(rw => 'MON');
	print "Setting MON mode for " , $Audio::Nama::this_bus , 
		" bus. No recording on user tracks.\n";
 	1  
}
bus_off: _bus_off end {
	$Audio::Nama::Bus::by_name{$Audio::Nama::this_bus}->set(rw => 'OFF'); 
	print "Setting OFF mode for " , $Audio::Nama::this_bus,
		" bus. All user tracks disabled.\n"; 1  }
bus_version: _bus_version end { 
	use warnings;
	no warnings qw(uninitialized);
	print $Audio::Nama::this_bus, " bus default version is: ", 
		$Audio::Nama::Bus::by_name{$Audio::Nama::this_bus}->version, "\n" ; 1}
bus_version: _bus_version dd end { 
	my $n = $item{dd};
	$n = undef if $n == 0;
	$Audio::Nama::Bus::by_name{$Audio::Nama::this_bus}->set( version => $n ); 
	print $Audio::Nama::this_bus, " bus default version set to: ", 
		$Audio::Nama::Bus::by_name{$Audio::Nama::this_bus}->version, "\n" ; 1}
mixdown: _mixdown end { Audio::Nama::Text::mixdown(); 1}
mixplay: _mixplay end { Audio::Nama::Text::mixplay(); 1}
mixoff:  _mixoff  end { Audio::Nama::Text::mixoff(); 1}
automix: _automix { Audio::Nama::automix(); 1 }
autofix_tracks: _autofix_tracks { Audio::Nama::command_process("for mon; fixdc; normalize"); 1 }
master_on: _master_on end { Audio::Nama::master_on(); 1 }
master_off: _master_off end { Audio::Nama::master_off(); 1 }
exit: _exit end {   Audio::Nama::save_state($Audio::Nama::state_store_file); 
					Audio::Nama::cleanup_exit();
                    1}	
source: _source portsfile end { $Audio::Nama::this_track->set_source($item{portsfile}); 1 }
portsfile: /\w+\.ports/
source: _source 'bus' end {$Audio::Nama::this_track->set(
		source_type => 'bus', 
		source_id => 'bus'); 1 }
source: _source 'null' end {
		$Audio::Nama::this_track->set(rec_defeat => 1,
					source_type => 'null',
					source_id => 'null');
 		print $Audio::Nama::this_track->name, ": Setting input to null device\n";
	}
source: _source jack_port end { $Audio::Nama::this_track->set_source( $item{jack_port} ); 1 }
source: _source end { 
	print $Audio::Nama::this_track->name, ": input set to ", $Audio::Nama::this_track->input_object, "\n";
	print "however track status is ", $Audio::Nama::this_track->rec_status, "\n"
		if $Audio::Nama::this_track->rec_status ne 'REC';
	1;
}
send: _send jack_port { $Audio::Nama::this_track->set_send($item{jack_port}); 1}
send: _send end { $Audio::Nama::this_track->set_send(); 1}
remove_send: _remove_send end {
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
off: 'off' end {$Audio::Nama::this_track->set_off(); 1}
rec: 'rec' end { $Audio::Nama::this_track->set_rec(); 1}
mon: 'mon' end {$Audio::Nama::this_track->set_mon(); 1}
rec_defeat: _rec_defeat end { 
	$Audio::Nama::this_track->set(rec_defeat => 1);
	print $Audio::Nama::this_track->name, ": WAV recording disabled!\n";
}
rec_enable: _rec_enable end { 
	$Audio::Nama::this_track->set(rec_defeat => 0);
	print $Audio::Nama::this_track->name, ": WAV recording enabled";
	my $rw = $Audio::Nama::Bus::by_name{$Audio::Nama::this_track->group}->rw;
	if ( $rw ne 'REC'){
		print qq(, but bus "),$Audio::Nama::this_track->group, qq(" has rw setting of $rw.\n),
		"No WAV file will be recorded.\n";
	} else { print "!\n" }
}
set_version: _set_version dd end { $Audio::Nama::this_track->set_version($item{dd}); 1}
vol: _vol sign(?) value end { 
	$Audio::Nama::this_track->vol or 
		print( $Audio::Nama::this_track->name . ": no volume control available\n"), return;
	$item{sign} = undef;
	$item{sign} = $item{'sign(?)'}->[0] if $item{'sign(?)'};
	Audio::Nama::modify_effect 
		$Audio::Nama::this_track->vol,
		0,
		$item{sign},
		$item{value};
	1;
} 
vol: _vol end { print $Audio::Nama::copp{$Audio::Nama::this_track->vol}[0], "\n" ; 1}
mute: _mute end { $Audio::Nama::this_track->mute; 1}
unmute: _unmute end { $Audio::Nama::this_track->unmute; 1}
solo: _solo end { Audio::Nama::solo(); 1}
all: _all end { Audio::Nama::all() ; 1}
unity: _unity end { 
	Audio::Nama::effect_update_copp_set( 
		$Audio::Nama::this_track->vol, 
		0, 
		$Audio::Nama::unity_level{$Audio::Nama::cops{$Audio::Nama::this_track->vol}->{type}}
	);
	1;}
pan: _pan dd end { 
	Audio::Nama::effect_update_copp_set( $Audio::Nama::this_track->pan, 0, $item{dd});
	1;} 
pan: _pan sign dd end {
	Audio::Nama::modify_effect( $Audio::Nama::this_track->pan, 0, $item{sign}, $item{dd} );
	1;} 
pan: _pan end { print $Audio::Nama::copp{$Audio::Nama::this_track->pan}[0], "\n"; 1}
pan_right: _pan_right end   { Audio::Nama::pan_check( 100 ); 1}
pan_left:  _pan_left  end   { Audio::Nama::pan_check(   0 ); 1}
pan_center: _pan_center end { Audio::Nama::pan_check(  50 ); 1}
pan_back:  _pan_back end {
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
remove_mark: _remove_mark dd end {
	my @marks = Audio::Nama::Mark::all();
	$marks[$item{dd}]->remove if defined $marks[$item{dd}];
	1;}
remove_mark: _remove_mark ident end { 
	my $mark = $Audio::Nama::Mark::by_name{$item{ident}};
	$mark->remove if defined $mark;
	1;}
remove_mark: _remove_mark end { 
	return unless (ref $Audio::Nama::this_mark) =~ /Mark/;
	$Audio::Nama::this_mark->remove;
	1;}
new_mark: _new_mark ident end { Audio::Nama::drop_mark $item{ident}; 1}
new_mark: _new_mark end {  Audio::Nama::drop_mark(); 1}
next_mark: _next_mark end { Audio::Nama::next_mark(); 1}
previous_mark: _previous_mark end { Audio::Nama::previous_mark(); 1}
loop_enable: _loop_enable someval(s) end {
	my @new_endpoints = @{ $item{"someval(s)"}}; 
	$Audio::Nama::loop_enable = 1;
	@Audio::Nama::loop_endpoints = (@new_endpoints, @Audio::Nama::loop_endpoints); 
	@Audio::Nama::loop_endpoints = @Audio::Nama::loop_endpoints[0,1];
	1;}
loop_disable: _loop_disable end { $Audio::Nama::loop_enable = 0; 1}
name_mark: _name_mark ident end {$Audio::Nama::this_mark->set_name( $item{ident}); 1}
list_marks: _list_marks end { 
	my $i = 0;
	map{ print( $_->time == $Audio::Nama::this_mark->time ? q(*) : q()
	,join " ", $i++, sprintf("%.1f", $_->time), $_->name, "\n")  } 
		  @Audio::Nama::Mark::all;
	my $start = my $end = "undefined";
	print "now at ", sprintf("%.1f", Audio::Nama::eval_iam "getpos"), "\n";
	1;}
to_mark: _to_mark dd end {
	my @marks = Audio::Nama::Mark::all();
	$marks[$item{dd}]->jump_here;
	1;}
to_mark: _to_mark ident end { 
	my $mark = $Audio::Nama::Mark::by_name{$item{ident}};
	$mark->jump_here if defined $mark;
	1;}
modify_mark: _modify_mark sign value end {
	my $newtime = eval($Audio::Nama::this_mark->time . $item{sign} . $item{value});
	$Audio::Nama::this_mark->set( time => $newtime );
	print $Audio::Nama::this_mark->name, ": set to ", Audio::Nama::d2( $newtime), "\n";
	Audio::Nama::eval_iam("setpos $newtime");
	$Audio::Nama::regenerate_setup++;
	1;
	}
modify_mark: _modify_mark value end {
	$Audio::Nama::this_mark->set( time => $item{value} );
	print $Audio::Nama::this_mark->name, ": set to ", Audio::Nama::d2( $item{value}), "\n";
	Audio::Nama::eval_iam("setpos $item{value}");
	$Audio::Nama::regenerate_setup++;
	1;
	}		
remove_effect: _remove_effect op_id(s) end {
	Audio::Nama::mute();
	map{ print "removing effect id: $_\n"; Audio::Nama::remove_effect( $_ )
	} grep { $_ }  @{ $item{"op_id(s)"}} ;
	Audio::Nama::sleeper(0.5);
	Audio::Nama::unmute();
	1;}
add_controller: _add_controller parent effect value(s?) end {
	my $code = $item{effect};
	my $parent = $item{parent};
	my $values = $item{"value(s?)"};
	Audio::Nama::Text::t_add_ctrl($parent, $code, $values);
	1;}
parent: op_id
add_effect: _add_effect effect value(s?) end {
	my $code = $item{effect};
	my $values = $item{"value(s?)"};
 	Audio::Nama::Text::t_add_effect($Audio::Nama::this_track, $code, $values);
 	1;}
insert_effect: _insert_effect before effect value(s?) end {
	my $before = $item{before};
	my $code = $item{effect};
	my $values = $item{"value(s?)"};
	print join ", ", @{$values} if $values;
	Audio::Nama::Text::t_insert_effect($before, $code, $values);
	1;}
before: op_id
modify_effect: _modify_effect op_id(s /,/) parameter(s /,/) value end {
	map{ my $op_id = $_;
		map{ my $parameter = $_;
			 $parameter--;
			 Audio::Nama::effect_update_copp_set( $op_id, $parameter, $item{value});
		} @{$item{"parameter(s)"}};
	} @{$item{"op_id(s)"}};
	1;
}
modify_effect: _modify_effect op_id(s /,/) parameter(s /,/) sign value end {
	map{ my $op_id = $_;
		map{ 	my $parameter = $_;
				$parameter--;
				Audio::Nama::modify_effect($op_id, $parameter, @item{qw(sign value)}); 
		} @{$item{"parameter(s)"}};
	} @{$item{"op_id(s)"}};
	1;
}
new_bunch: _new_bunch ident(s) { Audio::Nama::Text::bunch( @{$item{'ident(s)'}}); 1}
list_bunches: _list_bunches end { Audio::Nama::Text::bunch(); 1}
remove_bunches: _remove_bunches ident(s) { 
 	map{ delete $Audio::Nama::bunch{$_} } @{$item{'ident(s)'}}; 1}
add_to_bunch: _add_to_bunch ident(s) end { Audio::Nama::Text::add_to_bunch( @{$item{'ident(s)'}});1 }
list_versions: _list_versions end { 
	print join " ", @{$Audio::Nama::this_track->versions}, "\n"; 1}
ladspa_register: _ladspa_register end { 
	Audio::Nama::pager( Audio::Nama::eval_iam("ladspa-register")); 1}
preset_register: _preset_register end { 
	Audio::Nama::pager( Audio::Nama::eval_iam("preset-register")); 1}
ctrl_register: _ctrl_register end { 
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
import_audio: _import_audio path frequency end {
	$Audio::Nama::this_track->import_audio( $item{path}, $item{frequency}); 1;
}
import_audio: _import_audio path end {
	$Audio::Nama::this_track->import_audio( $item{path}); 1;
}
frequency: value
list_history: _list_history end {
	my @history = $Audio::Nama::term->GetHistory;
	my %seen;
	map { print "$_\n" unless $seen{$_}; $seen{$_}++ } @history
}
main_off: _main_off end { 
	$Audio::Nama::main_out = 0;
1;
} 
main_on: _main_on end { 
	$Audio::Nama::main_out = 1;
1;
} 
add_send_bus_cooked: _add_send_bus_cooked bus_name destination {
	Audio::Nama::add_send_bus( $item{bus_name}, $item{destination}, 'cooked' );
	1;
}
add_send_bus_raw: _add_send_bus_raw bus_name destination end {
	Audio::Nama::add_send_bus( $item{bus_name}, $item{destination}, 'raw' );
	1;
}
add_sub_bus: _add_sub_bus bus_name destination(?) end { 
	my $dest_id = $item{'destination(?)'}->[0];
	my $dest_type = $dest_id ?  Audio::Nama::dest_type($dest_id) : undef;
	Audio::Nama::add_sub_bus( $item{bus_name}, $dest_type, $dest_id); 1
}
existing_bus_name: bus_name {
	if ( $Audio::Nama::Bus::by_name{$item{bus_name}} ){  $item{bus_name} }
	else { print("$item{bus_name}: no such bus\n"); undef }
}
bus_name: /[A-Z]\w+/
destination: jack_port 
remove_bus: _remove_bus existing_bus_name end { 
	$Audio::Nama::Bus::by_name{$item{existing_bus_name}}->remove; 1; 
}
update_send_bus: _update_send_bus existing_bus_name end {
 	Audio::Nama::update_send_bus( $item{existing_bus_name} );
 	1;
}
set_bus: _set_bus key someval { $Audio::Nama::Bus::by_name{$Audio::Nama::this_bus}->set($item{key} => $item{someval}); 1 }
change_bus: _change_bus existing_bus_name { 
	return unless $Audio::Nama::this_bus ne $item{existing_bus_name};
	$Audio::Nama::this_bus = $item{existing_bus_name};
	$Audio::Nama::this_track = $Audio::Nama::tn{$item{existing_bus_name}} if
		(ref $Audio::Nama::Bus::by_name{$Audio::Nama::this_bus}) =~ /SubBus/;
	1 }
list_buses: _list_buses end { Audio::Nama::pager(map{ $_->dump } Audio::Nama::Bus::all()) ; 1}
add_insert: _add_insert prepost send_id return_id(?) end {
	my $return_id = "@{$item{'return_id(?)'}}";
	my $send_id = $item{send_id};
	Audio::Nama::Insert::add_insert( "$item{prepost}fader_insert",$send_id, $return_id);
	1;
}
prepost: 'pre' | 'post'
send_id: jack_port
return_id: jack_port
set_insert_wetness: _set_insert_wetness prepost(?) parameter end {
	my $prepost = "@$item{'prepost(?)'}";
	my $p = $item{parameter};
	my $id = Audio::Nama::Insert::get_id($Audio::Nama::this_track,$prepost);
	print($Audio::Nama::this_track->name.  ": Missing or ambiguous insert. Skipping\n"), 
		return 1 unless $id;
	print ("wetness parameter must be an integer between 0 and 100\n"), 
		return 1 unless ($p <= 100 and $p >= 0);
	my $i = $Audio::Nama::Insert::by_index{$id};
	print ("track '",$Audio::Nama::this_track->n, "' has no insert.  Skipping.\n"),
		return 1 unless $i;
	$i->{wetness} = $p;
	Audio::Nama::modify_effect($i->wet_vol, 0, undef, $p);
	Audio::Nama::sleeper(0.1);
	Audio::Nama::modify_effect($i->dry_vol, 0, undef, 100 - $p);
	1;
}
set_insert_wetness: _set_insert_wetness prepost(?) end {
	my $prepost = "@$item{'prepost(?)'}";
	my $id = Audio::Nama::Insert::get_id($Audio::Nama::this_track,$prepost);
	$id or print($Audio::Nama::this_track->name.  ": Missing or ambiguous insert. Skipping\n"), return 1 ;
	my $i = $Audio::Nama::Insert::by_index{$id};
	 print "The insert is ", 
		$i->wetness, "% wet, ", (100 - $i->wetness), "% dry.\n";
}
remove_insert: _remove_insert prepost(?) end { 
	my $prepost = "@{$item{'prepost(?)'}}";
	my $id = Audio::Nama::Insert::get_id($Audio::Nama::this_track,$prepost);
	$id or print($Audio::Nama::this_track->name.  ": Missing or ambiguous insert. Skipping\n"), return 1 ;
	print $Audio::Nama::this_track->name.": removing $prepost". "fader insert\n";
	$Audio::Nama::Insert::by_index{$id}->remove;
	1;
}
cache_track: _cache_track end { Audio::Nama::cache_track($Audio::Nama::this_track); 1 }
uncache_track: _uncache_track end { Audio::Nama::uncache_track($Audio::Nama::this_track); 1 }
new_effect_chain: _new_effect_chain ident op_id(s?) end {
	Audio::Nama::new_effect_chain($Audio::Nama::this_track, $item{ident}, @{ $item{'op_id(s?)'} });
	1;
}
add_effect_chain: _add_effect_chain ident end {
	Audio::Nama::add_effect_chain($Audio::Nama::this_track, $item{ident});
	1;
}
delete_effect_chain: _delete_effect_chain ident(s) end {
	map{ delete $Audio::Nama::effect_chain{$_} } @{ $item{'ident(s)'} };
	1;
}
list_effect_chains: _list_effect_chains ident(s?) end {
	Audio::Nama::list_effect_chains( @{ $item{'ident(s?)'} } ); 1;
}
bypass_effects:   _bypass_effects end { 
	Audio::Nama::push_effect_chain($Audio::Nama::this_track) and
	print $Audio::Nama::this_track->name, ": bypassing effects\n"; 1}
restore_effects: _restore_effects end { 
	Audio::Nama::restore_effects($Audio::Nama::this_track) and
	print $Audio::Nama::this_track->name, ": restoring effects\n"; 1}
overwrite_effect_chain: _overwrite_effect_chain ident end {
	Audio::Nama::overwrite_effect_chain($Audio::Nama::this_track, $item{ident}); 1;
}
bunch_name: ident { 
	Audio::Nama::is_bunch($item{ident}) or Audio::Nama::bunch_tracks($item{ident})
		or print("$item{ident}: no such bunch name.\n"), return; 
	$item{ident};
}
effect_profile_name: ident
existing_effect_profile_name: ident {
	print ("$item{ident}: no such effect profile\n"), return
		unless $Audio::Nama::effect_profile{$item{ident}};
	$item{ident}
}
new_effect_profile: _new_effect_profile bunch_name effect_profile_name end {
	Audio::Nama::new_effect_profile($item{bunch_name}, $item{effect_profile_name}); 1 }
delete_effect_profile: _delete_effect_profile existing_effect_profile_name end {
	Audio::Nama::delete_effect_profile($item{existing_effect_profile_name}); 1 }
apply_effect_profile: _apply_effect_profile effect_profile_name end {
	Audio::Nama::apply_effect_profile(\&Audio::Nama::overwrite_effect_chain, $item{effect_profile_name}); 1 }
overlay_effect_profile: _overlay_effect_profile effect_profile_name end {
	Audio::Nama::apply_effect_profile(\&Audio::Nama::add_effect_chain, $item{effect_profile_name}); 1 }
list_effect_profiles: _list_effect_profiles end {
	Audio::Nama::list_effect_profiles(); 1 }
do_script: _do_script shellish end { Audio::Nama::do_script($item{shellish});1}
scan: _scan end { print "scanning ", Audio::Nama::this_wav_dir(), "\n"; Audio::Nama::rememoize() }
add_fade: _add_fade in_or_out mark1 duration(?)
	{ Audio::Nama::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					duration => $item{'duration(?)'}->[0] 
								|| $Audio::Nama::default_fade_length, 
					relation => 'fade_from_mark',
					track => $Audio::Nama::this_track->name,
	)}
add_fade: _add_fade in_or_out duration(?) mark1 
	{ Audio::Nama::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					duration => $item{'duration(?)'}->[0] 
								|| $Audio::Nama::default_fade_length, 
					track => $Audio::Nama::this_track->name,
					relation => 'fade_to_mark',
	)}
add_fade: _add_fade in_or_out mark1 mark2
	{ Audio::Nama::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					mark2 => $item{mark2},
					track => $Audio::Nama::this_track->name,
	)}
in_or_out: 'in' | 'out'
duration: value
mark1: ident
mark2: ident
remove_fade: _remove_fade fade_index  { 
       return unless $item{fade_index};
       print "removing fade $item{fade_index} from track "
               .$Audio::Nama::Fade::by_index{$item{fade_index}}->track ."\n"; 
       Audio::Nama::Fade::remove($item{fade_index}) 
}
fade_index: dd 
 { if ( $Audio::Nama::Fade::by_index{$item{dd}} ){ return $item{dd}}
   else { print ("invalid fade number: $item{dd}\n"); return 0 }
 }
list_fade: _list_fade {  Audio::Nama::pager(join "\n",map{$_->dump} values %Audio::Nama::Fade::by_index) }

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
command: all
command: pan
command: pan_right
command: pan_left
command: pan_center
command: pan_back
command: show_tracks
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
command: change_bus
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
_set_track: /set_track\b/ | /set\b/
_rec: /rec\b/
_mon: /mon\b/ | /on\b/
_off: /off\b/ | /z\b/
_rec_defeat: /rec_defeat\b/ | /rd\b/
_rec_enable: /rec_enable\b/ | /re\b/
_source: /source\b/ | /src\b/ | /r\b/
_send: /send\b/ | /out\b/ | /aux\b/ | /m\b/
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
_solo: /solo\b/
_all: /all\b/ | /nosolo\b/
_pan: /pan\b/ | /p\b/
_pan_right: /pan_right\b/ | /pr\b/
_pan_left: /pan_left\b/ | /pl\b/
_pan_center: /pan_center\b/ | /pc\b/
_pan_back: /pan_back\b/ | /pb\b/
_show_tracks: /show_tracks\b/ | /show\b/ | /tracks\b/ | /list_tracks\b/ | /lt\b/
_show_track: /show_track\b/ | /sh\b/
_show_mode: /show_mode\b/ | /shm\b/
_set_region: /set_region\b/ | /srg\b/
_new_region: /new_region\b/ | /nrg\b/
_remove_region: /remove_region\b/ | /rrg\b/
_shift_track: /shift_track\b/ | /shift\b/
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
_change_bus: /change_bus\b/ | /cbs\b/
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

# end

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

__[end_data_section]__
__END__

=head1 NAME

B<Nama> - Ecasound-based recorder, mixer and mastering system

=head1 SYNOPSIS

B<nama> [I<options>] [I<project_name>]

=head1 DESCRIPTION

B<Nama> is a text-based application for multitrack
recording, effects processing, non-destructive editing and
mastering using Ecasound for all audio processing. Nama
offers the stable functioning of Ecasound enchanced by high
level concepts such as tracks and buses and a convenient
command language.
 
Nama has many functions found in digital-audio workstations
including marks, regions, fades, sends, inserts, buses,
track freezing and time shifting as well as some functions
unique to Nama.  Full help is provided, including commands
by category and search.

Nama runs under ALSA and JACK audio frameworks, and
automatically discovers all available LADSPA plugins.

Nama has a simple graphic interface based on the Tk
widget set. By default the GUI displays while the command
processor runs in a terminal window. The B<-t> option provides
a text-only interface for console users.

=head1 OPTIONS

=over 12

=item B<--gui, -g>

Start Nama in GUI mode

=item B<--text, -t>

Start Nama in text mode

=item B<--config, -f>

Specify configuration file (default: ~/.namarc)

=item B<--project-root, -d>

Specify project root directory

=item B<--create-project, -c>

Create project if it doesn't exist

=item B<--net-eci, -n>

Use Ecasound's Net-ECI interface

=item B<--libecasoundc, -l>

Use Ecasound's libecasoundc interface

=item B<--save-alsa, -a>

Save/restore alsa state with project data

=item B<--help, -h>

This help display

=back

Debugging options:

=over 12

=item B<--no-static-effects-data, -s>

Don't load effects data

=item B<--no-state, -m>

Don't load project state

=item B<--no-static-effects-cache, -e>

Bypass effects data cache

=item B<--regenerate-effects-cache, -r>

Regenerate the effects data cache

=item B<--no-reconfigure-engine, -R>

Don't automatically configure engine

=item B<--debugging-output, -D>

Emit debugging information

=item B<--fake-jack, -J>

Simulate JACK environment

=item B<--fake-alsa, -A>

Simulate ALSA environment

=item B<--no-ecasound, -E>

Don't spawn Ecasound process

=item B<--execute-command, -X>

Supply a command to execute

=back

=head1 CONTROLLING NAMA/ECASOUND

The Ecasound audio engine is configured through use of
I<chain setups> that specify the signal processing network.
After lauching the engine, realtime control capabilities are
available, for example to adjust signal volume and to set playback
position.

Nama serves as an intermediary, taking high-level commands
from the user, generating appropriate chain setups for
recording, playback, mixing, etc. and running the audio
engine.

Nama commands can be divided into two categories.

=head2 STATIC COMMANDS

Static commands affect I<future> runs of the audio
processing engine. For example, B<rec, mon> and B<off>
determine whether the current track will get its audio
stream from a live source or whether an existing WAV file
will be played back. Nama responds to static commands by
automatically reconfiguring the engine and displaying the
updated track status.

=head2 DYNAMIC COMMANDS

Once a chain setup is loaded and the engine is launched,
another set of commands controls the realtime behavior of
the audio processing engine. Commonly used I<dynamic
commands> include transport C<start> and C<stop>; playback
head repositioning commands such C<forward>, C<rewind> and
C<setpos>. Effects may be added, modified or removed 
while the engine is running.

=head2 CONFIGURATION

General configuration of sound devices and program options
is performed by editing the F<.namarc> file. On Nama's first
run, a default version of F<.namarc> is usually placed in
the user's home directory. 

=head1 Tk GRAPHICAL UI 

Invoked by default if Tk is installed, this interface
provides a subset of Nama's functionality on two
panels, one for general control, the second for effects. 

The general panel has buttons for project create, load
and save, for adding tracks and effects, and for setting
the vol, pan and record status of each track.

The GUI project name bar and time display change color to indicate
whether the upcoming operation will include live recording
(red), mixdown only (yellow) or playback only (green).  Live
recording and mixdown can take place simultaneously.

The effects window provides sliders for each effect
parameters. Parameter range, defaults, and log/linear
scaling hints are automatically detected. Text-entry widgets
are used to enter parameters values for plugins without
hinted ranges.

The text command prompt appears in the terminal window
during GUI operation. Text commands may be issued at any
time.

=head1 TEXT UI

Press the I<Enter> key if necessary to get the following command prompt.

=over 12

C<nama [sax] ('h' for help)E<gt>>

=back

In this instance, 'sax' is the current track.

When using sub-buses, the bus is indicated before
the track:

=over 12

C<nama [Strings/violin] ('h' for help)E<gt>>

=back

At the prompt, you can enter Nama and Ecasound commands, Perl code
preceded by C<eval> or shell code preceded by C<!>.

Multiple commands on a single line are allowed if delimited
by semicolons. Usually the lines are split on semicolons and
the parts are executed sequentially, however if the line
begins with C<eval> or C<!> the entire line (up to double
semicolons ';;' if present) will be given to the
corresponding interpreter.

You can access command history using up-arrow/down-arrow.

Type C<help> for general help, C<help command> for help with
C<command>, C<help foo> for help with commands containing
the string C<foo>. C<help_effect foo bar> lists all 
plugins/presets/controller containing both I<foo> and
I<bar>. Tab-completion is provided for Nama commands, Ecasound-iam
commands, plugin/preset/controller names, and project names.

=head1 TRACKS

Each track has a descriptive name (i.e. vocal) and an
integer track-number assigned when the track is created.
The following paragraphs describes track attributes and
their settings.

=head2 WIDTH

Specifying 'mono' means a one-channel input, which is
recorded as a mono WAV file. Mono signals are duplicated to
stereo and a pan effect is provided for all user tracks.

Specifying 'stereo' for a track means that two channels of
audio input will be recorded as an interleaved stereo WAV file.

Specifying N channels for a track ('set width N') means
N successive input channels will be recorded as an N-channel 
interleaved WAV file.

=head2 VERSION NUMBER

Multiple WAV files can be recorded for each track. These are
distinguished by a version number that increments with each
recording run, i.e. F<sax_1.wav>, F<sax_2.wav>, etc.  All
WAV files recorded in the same run have the same version
numbers. 

The version numbers of files for playback can be selected at
the bus or track level. By setting the bus version
number to 5, you can play back the fifth take of a song, or
perhaps the fifth song of a live recording session. 

The track version setting, if present, overrides 
the bus setting. Setting the track version to zero
restores control of the version number to the 
bus setting.

A bus version setting for the Main bus does I<not>
propagate to sub-buses.

=head2 REC/MON/OFF

Track REC/MON/OFF status guides audio processing.

Each track, including Master and Mixdown, has its own
REC/MON/OFF setting and displays its own REC/MON/OFF status.
The Main bus also has REC, MON and OFF settings that
influence the behavior of all user tracks.

As the name suggests, I<REC> status indicates that a track
is ready to record a WAV file. You need to set both track and
bus to REC to record an audio stream to file.

I<MON> status indicates an audio stream available from disk.
It requires a MON setting for the track or bus as well as
the presence of a file with the selected version number.  A
track set to REC with no live input will default to MON
status.

I<OFF> status means that no audio is available for the track
from any source. A track with no recorded WAV files 
will show OFF status, even if set to MON.

An OFF setting for a track or bus always results in OFF
status, causing the track to be excluded from the
chain setup. I<Note: This setting is distinct from the action of
the C<mute> command, which sets the volume of the track to
zero.>

Newly created user tracks belong to the Main bus, which
goes through a mixer and Master fader track to the 
soundcard for monitoring.

=head2 MARKS

Marks in Nama are similar to those in other audio editing
software, with one small caveat: Mark positions are relative
to the beginning of an Ecasound chain setup. If your project
involves a single track, and you will be shortening the
stream by setting a region to play, set any marks you need
I<after> defining the region.

=head2 REGIONS

The C<region> command allows you to define endpoints
for a portion of an audio file. Use the C<shift> command
to specify a delay for starting playback.

Only one region may be specified per track.  Use the
C<new_region> command to clone a track, specifying
a new region definition. 

C<link_track> can clone tracks from other projects. 

=head2 EFFECTS

Each track gets volume and pan effects by default.  New
effects added using C<add_effect> are applied after pan 
volume controls.  You can position effects anywhere you choose
using C<insert_effect>.

=head3 FADERS

Nama allows you to place fades on any track. Fades are
logarithmic, defined by a mark position and a duration. 
An extra volume operator, -eadb is applied to the track to
enable this function.

=head3 SENDS AND INSERTS

The C<send> command can route a track's post-fader output
to a soundcard channel or JACK client in addition to the
normal mixer input. Nama currently allows one aux send per
track.

The C<add_insert_cooked> command configures a post-fader
send-and-return to soundcard channels or JACK clients.
Wet and dry signal paths are provided, with a default
setting of 100% wet.

=head1 BUS-LEVEL REC/MON/OFF SETTING

By default, all user tracks belong to Nama's Main bus. 
The Main bus has its own REC/MON/OFF setting
that influences the rec-status of individual tracks. 

Setting a bus to OFF forces all of the bus tracks to
OFF. When the bus is set to MON, track REC settings are
forced to MON.  When the bus is set to REC, track status
can be REC, MON or OFF. 

The Main bus MON mode triggers automatically after a successful
recording run.

The B<mixplay> command sets the Mixdown track to MON and the
Main bus to OFF.

=head2 BUNCHES

A bunch is just a list of track names. Bunch names are used
with the keyword C<for> to apply one or more commands to to several
tracks at once. A bunch can be created with the C<new_bunch>
command. Any bus name can also be treated as a bunch.
Finally, a number of special bunch keywords are available.

=over 12

=item B<rec>, B<mon>, B<off>

All tracks with the corresponding I<setting> in the current bus

=item B<REC>, B<MON>, B<OFF>

All tracks with the corresponding I<status> in the current bus

=back

=head2 BUSES

Nama uses buses internally, and provides two kinds of
user-defined buses. 

B<Sub buses> enable multiple tracks to be routed through a
single mix track before feeding the main mixer bus (or
possibly another sub bus.) 

The following commands create a sub bus and assign
three tracks to it. The mix track takes the name of
the bus. I<Strings> in this case, and is stereo
by default.

	add_sub_bus Strings
	add_tracks violin cello bass
	for violin cello bass; set bus Strings
	Strings vol - 10

B<Send buses> can be used as instrument monitors,
or to send pre- or post-fader signals from multiple
user tracks to an external program such as jconv.

=head1 ROUTING

Nama commands can address tracks by both a name and a
number. In Ecasound chain setups, only the track
number is used. 

=head2 Loop devices

Nama uses Ecasound loop devices to join two tracks, 
or to allow one track to have multiple inputs or
outputs. 

=head2 Flow diagrams

Let's examine the signal flow from track 3, the first 
available user track. Assume track 3 is named "sax".

We will divide the signal flow into track and mixer
sections.  Parentheses indicate chain identifiers or the
corresponding track name.

The stereo outputs of each user track terminate at 
Master_in, a loop device at the mixer input.

=head3 Track, REC status

    Sound device   --+---(3)----> Master_in
      /JACK client   |
                     +---(R3)---> sax_1.wav

REC status indicates that the source of the signal is the
soundcard or JACK client. The input signal will be written
directly to a file except in the special preview and doodle
modes.


=head3 Track, MON status

    sax_1.wav ------(3)----> Master_in

=head3 Mixer, with mixdown enabled

In the second part of the flow graph, the mixed signal is
delivered to an output device through the Master chain,
which can host effects. Usually the Master track
provides final control before audio output or mixdown.

    Master_in --(1/Master)--> Master_out -> Sound device
                                 |
                                 +----->(2/Mixdown)--> Mixdown_1.wav

During mastering, the mastering network is inserted
between the Master track, and the audio/mixdown output. 

=head3 Mastering Mode

In mastering mode (invoked by C<master_on> and released
C<master_off>) the following network is used:

                          +-(Low)-+ 
                          |       |
    Eq-in -(Eq)-> Eq_out -+-(Mid)-+- Boost_in -(Boost)-> soundcard/wav_out
                          |       |
                          +-(High)+ 

The B<Eq> track hosts an equalizer.

The B<Low>, B<Mid> and B<High> tracks each apply a bandpass
filter, a compressor and a spatialiser.

The B<Boost> track applies gain and a limiter.

These effects and their default parameters are defined
in the configuration file F<.namarc>.

=head2 Mixdown

The C<mixdown> command configures Nama for mixdown. 
The Mixdown track is set to REC (equivalent to C<Mixdown rec>) and the audio
monitoring output is turned off (equivalent to C<main_off>).

Mixdown proceeds after you enter the C<start> command.

=head2 Preview and Doodle Modes

These non-recording modes, invoked by C<preview> and C<doodle> commands
tweak the routing rules for special purposes.  B<Preview
mode> disables recording of WAV files to disk.  B<Doodle
mode> disables MON inputs while enabling only one REC track per
signal source. The C<arm> command releases both preview
and doodle modes.

=head1 TEXT COMMANDS

[% qx(./emit_command_headers pod) %]

=head1 DIAGNOSTICS

In most situations, the GUI display and the output of the
C<show_tracks> command (executed automatically on any change
in setup) show what to expect the next time the engine is
started.

Additionally, Nama has a number of diagnostic functions that
can help resolve problems without resorting to the debugging
flag (and wading through its prolific output.) The C<chains>
command displays the current chain setup to determine if
Ecasound is properly configured for the task at hand. (It
is much easier to read these setups than to write them!)

The C<dump> command displays data for the current track.
The C<dumpall> command shows all state that would be saved.
This is the same output that is written to the F<State.yml>
file when you issue the C<save> command.

=head1 BUGS AND LIMITATIONS

No waveform or signal level displays are provided.  

No latency compensation across signal paths is provided at
present, although this feature is planned.

=head1 SECURITY CONCERNS

If you are using Nama with the NetECI interface (i.e. if
Audio::Ecasound is I<not> installed) you should block TCP
port 2868 if your computer is exposed to the Internet. 

=head1 INSTALLATION

The following command, available on Unixlike systems with
Perl installed, will pull in Nama and other Perl libraries
required for text mode operation:

PERL_MM_USE_DEFAULT=1 cpan Audio::Nama

To use the GUI, you will need to install Tk:

C<cpan Tk>

You may want to install Audio::Ecasound if you prefer not to
run Ecasound in server mode:

C<cpan Audio::Ecasound>

You can pull the source code as follows: 

C<git clone git://github.com/bolangi/nama.git>

Consult the F<BUILD> file for build instructions.

=head1 SUPPORT

The Ecasound mailing list is a suitable forum for questions
regarding Nama installation, usage, feature requests, etc.,
as well as questions relating to Ecasound itself.

https://lists.sourceforge.net/lists/listinfo/ecasound-list

=head1 PATCHES

The main module, Nama.pm, and its sister modules are
concatenations of several source files. Patches against
these source files are preferred.

=head1 AUTHOR

Joel Roth, E<lt>joelz@pobox.comE<gt>