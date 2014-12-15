package Audio::Nama;
require 5.10.0;
use vars qw($VERSION);
$VERSION = "1.100";
use Modern::Perl;
#use Carp::Always;
no warnings qw(uninitialized syntax);
use autodie qw(:default);

########## External dependencies ##########

use Carp;
use Cwd;
use Data::Section::Simple qw(get_data_section);
use File::Find::Rule;
use File::Path;
use File::Spec;
use File::Spec::Link;
use File::Temp;
use Getopt::Long;
use Git::Repository;
use Graph;
use IO::Socket; 
use IO::Select;
use IPC::Open3;
use Log::Log4perl qw(get_logger :levels);
use Module::Load::Conditional qw(can_load); 
use Parse::RecDescent;
use Storable qw(thaw);
use Term::ReadLine;
use Text::Format;
use Try::Tiny;
# use File::HomeDir;# Assign.pm
# use File::Slurp;  # several
# use List::Util;   # Fade.pm
# use List::MoreUtils; # Effects.pm
# use Time::HiRes; # automatically detected
# use Tk;           # loaded conditionally
# use Event;		# loaded conditionally
# use AnyEvent;		# loaded after Tk or Event

########## Nama modules ###########
#
# Note that :: in the *.p source files is expanded by       # SKIP_PREPROC
# preprocessing to Audio::Nama in the generated *.pm files. # SKIP_PREPROC
# ::Assign becomes Audio::Nama::Assign                      # SKIP_PREPROC
#
# These modules import functions and variables
#

use Audio::Nama::Assign qw(:all);
use Audio::Nama::Globals qw(:all);
use Audio::Nama::Util qw(:all);

# Import the two user-interface classes

use Audio::Nama::Text;
use Audio::Nama::Graphical;

# They are descendents of a base class we define in the root namespace

our @ISA; # no ancestors
use Audio::Nama::Object qw(mode); # based on Object::Tiny

sub hello {"superclass hello"}

sub new { my $class = shift; return bless {@_}, $class }

# The singleton $ui belongs to either the Audio::Nama::Text or Audio::Nama::Graphical class
# depending on command line flags (-t or -g).
# This (along with the availability of Tk) 
# determines whether the GUI comes up. The Text UI
# is *always* available in the terminal that launched
# Nama.

# How is $ui->init_gui interpreted? If $ui belongs to class
# Audio::Nama::Text, Nama finds a no-op init_gui() stub in package Audio::Nama::Text
# and does nothing.

# If $ui belongs to class Audio::Nama::Graphical, Nama looks for
# init_gui() in package Audio::Nama::Graphical, finds nothing, so goes to
# look in the base class.  All graphical methods (found in
# Graphical_subs.pl) are defined in the root namespace so they can
# call Nama core methods without a package prefix.

######## Nama classes ########

use Audio::Nama::Track;
use Audio::Nama::Bus;    
use Audio::Nama::Mark;
use Audio::Nama::IO;
use Audio::Nama::Wav;
use Audio::Nama::Insert;
use Audio::Nama::Fade;
use Audio::Nama::Edit;
use Audio::Nama::EffectChain;

####### Nama subroutines ######
#
# The following modules serve only to define and segregate subroutines. 
# They occupy the root namespace (except Audio::Nama::ChainSetup)
# and do not execute any code when use'd.
#

use Audio::Nama::Initializations ();
use Audio::Nama::Options ();
use Audio::Nama::Config ();
use Audio::Nama::Custom ();
use Audio::Nama::Terminal ();
use Audio::Nama::Grammar ();
use Audio::Nama::Help ();

use Audio::Nama::Project ();
use Audio::Nama::Persistence ();

use Audio::Nama::ChainSetup (); # separate namespace
use Audio::Nama::Graph ();
use Audio::Nama::Modes ();
use Audio::Nama::Memoize ();

use Audio::Nama::Engine_setup ();
use Audio::Nama::Engine_cleanup ();
use Audio::Nama::Effects_registry ();
use Audio::Nama::Effects ();
use Audio::Nama::Engine ();
use Audio::Nama::Mute_Solo_Fade ();
use Audio::Nama::Jack ();

use Audio::Nama::Regions ();
use Audio::Nama::CacheTrack ();
use Audio::Nama::Bunch ();
use Audio::Nama::Wavinfo ();
use Audio::Nama::Midi ();
use Audio::Nama::Latency ();
use Audio::Nama::Log qw(logit logsub initialize_logger);

sub main { 
	definitions();
	process_command_line_options();
	setup_grammar();
	initialize_interfaces();
	command_process($config->{execute_on_project_load});
	reconfigure_engine();
	command_process($config->{opts}->{X});
	$ui->loop;
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
	} @{$engine->{pids}};
 	#kill 15, ecasound_pid() if $engine->{socket};  	
	close_midish() if $config->{use_midish};
	$text->{term}->rl_deprep_terminal() if defined $text->{term};
	exit; 
}
END { cleanup_exit() }


1;
__DATA__
@@ commands_yml
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
restart_ecasound:
  type: transport
  what: re-spawn ecasound engine
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
  short: lt show
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
show_track_latency:
  type: track
  short: shl
  what: show latency data for current track
show_latency_all:
  type: diagnostics
  short: shla
  what: dump all latency data
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
arm_start:
  short: arms
  type: setup
  what: generate/connect chain setup and start engine
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
  what: add a controller to an operator (current operator, by default) use mfx to modify, rfx to remove)
  parameters: [<s_operator_id>] <s_effect_code> [ <f_param1> <f_param2>...]
  short: acl
add_effect:
  short: afx
  type: effect
  what: add effect before fader (vol/pan controls)
  parameters: <s_effect_code> [ <f_param1> <f_param2>... ]
  example: |2
    add_effect amp 6     ; LADSPA Simple amp 6dB gain
    add_effect var_dali  ; preset var_dali. Note that you don't need
                         ; Ecasound's el: or pn: prefix
append_effect:
  short: apfx
  type: effect
  what: add effect after fader
  parameters: <s_effect_code> [ <f_param1> <f_param2>... ]
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
  parameters: [<s_id_to_move>, <s_position_id>]
show_effect:
  type: effect
  what: show effect information
  short: sfx
  parameters: <s_effect_id1> [ <s_effect_id2>...]
list_effects:
  type: effect
  what: short list of effects on current track
  short: lfx
  parameters: none
add_insert:
  type: effect 
  short: ain
  what: add an external send/return to current track
  parameters: ( pre | post ) <s_send_id> [<s_return_id>] -or- local (for wet/dry control)
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
  parameters: <s_effect_chain_name>
overwrite_effect_chain:
  type: effect
  short: oec
  what: add an effect chain overwriting current effects (which are pushed onto the bypass list)
  parameters: <s_effect_chain_name>
delete_effect_chain:
  type: effect
  short: dec
  what: delete an effect chain definition from the list
  parameters: <s_effect_chain_name>
find_effect_chains:
  type: effect
  short: fec
  what: dump effect chains, matching key/value pairs if provided
  parameters: [<s_key1> <s_val1>... ]
find_user_effect_chains:
  type: effect
  short: fuc
  what: list *user* effect chains, matching key/value pairs if provided
  parameters: [<s_key1> <s_val1>... ]
bypass_effects:
  type: effect
  short: bypass bfx
  what: bypass effects on current track (default to current effect)
  parameters: [<s_id1> <s_id2>... | 'all' ]
bring_back_effects:
  type: effect
  short: restore_effects bbfx
  what: restore effects (default to current effect)
  parameters: [<s_id1> <s_id2>... | 'all' ]
new_effect_profile:
  type: effect
  short: nep
  what: create a named group of effect chains for multiple tracks
  parameters: <s_bunch_name> [<s_effect_profile_name>]
apply_effect_profile:
  type: effect
  short: aep
  what: use an effect profile to add effects to multiple tracks
  parameters: <s_effect_profile_name>
delete_effect_profile:
  type: effect
  short: dep
  what: delete an effect profile
  parameters: <s_effect_profile_name>
list_effect_profiles:
  type: effect
  short: lep
  what: list effect profile 
show_effect_profiles:
  type: effect
  short: sepr
  what: list effect profile 
full_effect_profiles:
  type: effect
  short: fep
  what: dump effect profile data structure
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
view_waveform:
  type: general
  short: wview
  what: launch mhwavedit to view/edit waveform of current track/version WAV file
edit_waveform:
  type: general
  short: wedit
  what: launch audacity to view/edit waveform of current track/version WAV file
rerecord:
  type: setup
  short: rerec
  what: record as previously, restoring tracks to REC
eager:
  type: general
  what: output signals as soon as possible
  parameters: off | doodle | preview
...

@@ grammar

meta: midish_cmd 
midish_cmd: /[a-z]+/ predicate { 
	return unless $Audio::Nama::midi->{keywords}->{$item[1]};
	my $line = "$item[1] $item{predicate}";
	Audio::Nama::midish_command($line);
	1;
}
meta: bang shellcode stopper {
	Audio::Nama::logit(__LINE__,'Audio::Nama::Grammar','debug',"Evaluating shell commands!");
	my $shellcode = $item{shellcode};
	$shellcode =~ s/\$thiswav/$Audio::Nama::this_track->full_path/e;
	Audio::Nama::pager2( "executing this shell code:  $shellcode" )
		if $shellcode ne $item{shellcode};
	my $output = qx( $shellcode );
	Audio::Nama::pager($output) if $output;
	print "\n";
	1;
}
meta: eval perlcode stopper {
	Audio::Nama::logit(__LINE__,'Audio::Nama::Grammar','debug',"Evaluating perl code");
	Audio::Nama::eval_perl($item{perlcode});
	1
}
meta: for bunch_spec ';' namacode stopper { 
 	Audio::Nama::logit(__LINE__,'Audio::Nama::Grammar','debug',"namacode: $item{namacode}");
 	my @tracks = Audio::Nama::bunch_tracks($item{bunch_spec});
 	for my $t(@tracks) {
 		Audio::Nama::leading_track_spec($t);
		$Audio::Nama::text->{parser}->meta($item{namacode});
	}
	1;
}
bunch_spec: text 
meta: nosemi(s /\s*;\s*/) semicolon(?) 
nosemi: text { $Audio::Nama::text->{parser}->do_part($item{text}) }
text: /[^;]+/ 
semicolon: ';'
do_part: track_spec command end
do_part: track_spec end
do_part: command end
predicate: nonsemi end { $item{nonsemi}}
predicate: /$/
iam_cmd: ident { $item{ident} if $Audio::Nama::text->{iam}->{$item{ident}} }
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
	Audio::Nama::logit(__LINE__,'Audio::Nama::Grammar','debug',"Found Ecasound IAM command: $user_input");
	my $result = Audio::Nama::eval_iam($user_input);
	Audio::Nama::pager( $result );  
	1 }
command: user_command predicate {
	Audio::Nama::do_user_command(split " ",$item{predicate});
	1;
}
command: user_alias predicate {
	$Audio::Nama::text->{parser}->do_part("$item{user_alias} $item{predicate}"); 1
}
user_alias: ident { 
		$Audio::Nama::text->{user_alias}->{$item{ident}} }
user_command: ident { return $item{ident} if $Audio::Nama::text->{user_command}->{$item{ident}} }
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
effect: /\w[^, ]+/ | <error: illegal identifier, only word characters and colon allowed>
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
connect_target: connect_type connect_id { [ @item{qw(connect_type connect_id)} ] }
connect_type: 'track' | 'loop' | 'jack' 
connect_id: shellish 
help_effect: _help_effect effect { Audio::Nama::help_effect($item{effect}) ; 1}
find_effect: _find_effect anytag(s) { 
	Audio::Nama::find_effect(@{$item{"anytag(s)"}}); 1}
help: _help 'yml' { Audio::Nama::pager($Audio::Nama::text->{commands_yml}); 1}
help: _help anytag  { Audio::Nama::help($item{anytag}) ; 1}
help: _help { print $Audio::Nama::help->{screen} ; 1}
project_name: _project_name { 
	print "project name: ", $Audio::Nama::gui->{_project_name}->{name}, $/; 1}
create_project: _create_project project_id { 
	Audio::Nama::t_create_project $item{project_id} ; 1}
list_projects: _list_projects { Audio::Nama::list_projects() ; 1}
load_project: _load_project project_id {
	Audio::Nama::t_load_project $item{project_id} ; 1}
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
 		name => $Audio::Nama::gui->{_project_name}->{name},
 		settings => $item{statefile}
 		); 1}
get_state: _get_state {
 	Audio::Nama::load_project( name => $Audio::Nama::gui->{_project_name}->{name},) ; 1}
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
dump_group: _dump_group { Audio::Nama::pager($Audio::Nama::bn{Main}->dump); 1}
dump_all: _dump_all { Audio::Nama::dump_all(); 1}
remove_track: _remove_track quiet(?) { 
 	my $quiet = scalar @{$item{'quiet(?)'}};
 	$Audio::Nama::this_track->remove, return 1 if $quiet or $Audio::Nama::config->{quietly_remove_tracks};
 	my $name = $Audio::Nama::this_track->name; 
 	my $reply = $Audio::Nama::text->{term}->readline("remove track $name? [n] ");
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
		Audio::Nama::pager2($Audio::Nama::this_track->name, ": Shifting start time to $pos seconds");
		$Audio::Nama::this_track->set(playat => $pos);
		1;
	}
	elsif ( $Audio::Nama::Mark::by_name{$pos} ){
		my $time = Audio::Nama::Mark::mark_time( $pos );
		pager2($Audio::Nama::this_track->name, qq(: Shifting start time to mark "$pos", $time seconds));
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
arm_start: _arm_start { Audio::Nama::arm(); Audio::Nama::start_transport(); 1 }
connect: _connect { Audio::Nama::connect_transport(); 1}
disconnect: _disconnect { Audio::Nama::disconnect_transport(); 1}
engine_status: _engine_status { 
	print(Audio::Nama::eval_iam q(engine-status)); print "\n" ; 1}
start: _start { Audio::Nama::start_transport(); 1}
stop: _stop { Audio::Nama::stop_transport(); 1}
ecasound_start: _ecasound_start { Audio::Nama::eval_iam('start'); 1}
ecasound_stop: _ecasound_stop  { Audio::Nama::eval_iam('stop'); 1}
restart_ecasound: _restart_ecasound { Audio::Nama::restart_ecasound(); 1 }
show_tracks: _show_tracks { 	
	Audio::Nama::pager( Audio::Nama::show_tracks(Audio::Nama::showlist()));
	1;
}
show_tracks_all: _show_tracks_all { 	
	my $list = [undef, undef, sort{$a->n <=> $b->n} Audio::Nama::Track::all()];
	Audio::Nama::pager(Audio::Nama::show_tracks($list));
	1;
}
show_bus_tracks: _show_bus_tracks { 	
	my $bus = $Audio::Nama::bn{$Audio::Nama::this_bus};
	my $list = $bus->trackslist;
	Audio::Nama::pager(Audio::Nama::show_tracks($list));
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
	my $output = $Audio::Nama::text->{format_top};
	$output .= Audio::Nama::show_tracks_section($Audio::Nama::this_track);
	$output .= Audio::Nama::show_region();
	$output .= Audio::Nama::show_effects();
	$output .= Audio::Nama::show_versions();
	$output .= Audio::Nama::show_send();
	$output .= Audio::Nama::show_bus();
	$output .= Audio::Nama::show_modifiers();
	$output .= join "", "Signal width: ", Audio::Nama::width($Audio::Nama::this_track->width), "\n";
	$output .= Audio::Nama::show_inserts();
	Audio::Nama::pager( $output );
	1;}
show_track: _show_track track_name { 
 	Audio::Nama::pager( Audio::Nama::show_tracks( 
	$Audio::Nama::tn{$item{track_name}} )) if $Audio::Nama::tn{$item{track_name}};
	1;}
show_track: _show_track dd {  
	Audio::Nama::pager( Audio::Nama::show_tracks( $Audio::Nama::ti{$item{dd}} )) if
	$Audio::Nama::ti{$item{dd}};
	1;}
show_mode: _show_mode { print STDOUT Audio::Nama::show_status; 1}
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
mixdown: _mixdown { Audio::Nama::mixdown(); 1}
mixplay: _mixplay { Audio::Nama::mixplay(); 1}
mixoff:  _mixoff  { Audio::Nama::mixoff(); 1}
automix: _automix { Audio::Nama::automix(); 1 }
autofix_tracks: _autofix_tracks { Audio::Nama::command_process("for mon; fixdc; normalize"); 1 }
master_on: _master_on { Audio::Nama::master_on(); 1 }
master_off: _master_off { Audio::Nama::master_off(); 1 }
exit: _exit {   
	Audio::Nama::save_state(); 
	Audio::Nama::cleanup_exit();
	1
}	
source: _source connect_target { 
	$Audio::Nama::this_track->set_source(@{$item{connect_target}}); 1 }
source: _source source_id { $Audio::Nama::this_track->set_source($item{source_id}); 1 }
source_id: shellish
source: _source { 
	print $Audio::Nama::this_track->name, ": input set to ", $Audio::Nama::this_track->input_object_text, "\n";
	print "however track status is ", $Audio::Nama::this_track->rec_status, "\n"
		if $Audio::Nama::this_track->rec_status ne 'REC';
	1;
}
send: _send connect_target { 
	$Audio::Nama::this_track->set_send(@{$item{connect_target}}); 1 }
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
	$Audio::Nama::this_track->is_system_track 
		? $Audio::Nama::this_track->set(rw => uc $item{rw_setting}) 
		: Audio::Nama::rw_set($Audio::Nama::Bus::by_name{$Audio::Nama::this_bus},$Audio::Nama::this_track,$item{rw_setting}); 
	1
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
vol: _vol { print $Audio::Nama::fx->{params}->{$Audio::Nama::this_track->vol}[0], "\n" ; 1}
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
		$Audio::Nama::config->{unity_level}->{Audio::Nama::type($Audio::Nama::this_track->vol)}
	);
	1;}
pan: _pan panval { 
	Audio::Nama::effect_update_copp_set( $Audio::Nama::this_track->pan, 0, $item{panval});
	1;} 
pan: _pan sign panval {
	Audio::Nama::modify_effect( $Audio::Nama::this_track->pan, 0, $item{sign}, $item{panval} );
	1;} 
panval: float 
      | dd
pan: _pan { print $Audio::Nama::fx->{params}->{$Audio::Nama::this_track->pan}[0], "\n"; 1}
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
	$Audio::Nama::mode->{loop_enable} = 1;
	@{$Audio::Nama::setup->{loop_endpoints}} = (@new_endpoints, @{$Audio::Nama::setup->{loop_endpoints}}); 
	@{$Audio::Nama::setup->{loop_endpoints}} = @{$Audio::Nama::setup->{loop_endpoints}}[0,1];
	1;}
loop_disable: _loop_disable { $Audio::Nama::mode->{loop_enable} = 0; 1}
name_mark: _name_mark ident {$Audio::Nama::this_mark->set_name( $item{ident}); 1}
list_marks: _list_marks { 
	my $i = 0;
	my @lines = map{ ( $_->{time} == $Audio::Nama::this_mark->{time} ? q(*) : q()
	,join " ", $i++, sprintf("%.1f", $_->{time}), $_->name, "\n")  } 
		  @Audio::Nama::Mark::all;
	my $start = my $end = "undefined";
	push @lines, "now at ". sprintf("%.1f", Audio::Nama::eval_iam "getpos"). "\n";
	Audio::Nama::pager(@lines);
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
	Audio::Nama::set_position($Audio::Nama::this_mark->time);
	$Audio::Nama::setup->{changed}++;
	1;
	}
modify_mark: _modify_mark value {
	$Audio::Nama::this_mark->set( time => $item{value} );
	my $newtime = $item{value};
	print $Audio::Nama::this_mark->name, ": set to ", Audio::Nama::d2($newtime),"\n";
	print "adjusted to ",$Audio::Nama::this_mark->time, "\n" 
		if $Audio::Nama::this_mark->time != $newtime;
	Audio::Nama::set_position($Audio::Nama::this_mark->time);
	$Audio::Nama::setup->{changed}++;
	1;
	}		
remove_effect: _remove_effect op_id(s) {
	Audio::Nama::mute();
	map{ 
		Audio::Nama::remove_effect( $_ )
	} grep { $_ }  @{ $item{"op_id(s)"}} ;
	Audio::Nama::sleeper(0.5);
	Audio::Nama::unmute();
	1;}
add_controller: _add_controller parent effect value(s?) {
	my $code = $item{effect};
	my $parent = $item{parent};
	my $values = $item{"value(s?)"};
	my $id = Audio::Nama::add_effect({
		parent_id => $parent, 
		type	  => $code, 
		values	  => $values,
	});
	if($id)
	{
		my $i = 	Audio::Nama::effect_index($code);
		my $iname = $Audio::Nama::fx_cache->{registry}->[$i]->{name};
		my $pi = 	Audio::Nama::effect_index(Audio::Nama::type($parent));
		my $pname = $Audio::Nama::fx_cache->{registry}->[$pi]->{name};
		print "\nAdded $id ($iname) to $parent ($pname)\n\n";
	}
	1;
}
add_controller: _add_controller effect value(s?) {
	print("current effect is undefined, skipping\n"), return 1 if ! $Audio::Nama::this_op;
	my $code = $item{effect};
	my $parent = $Audio::Nama::this_op;
	my $values = $item{"value(s?)"};
	my $id = Audio::Nama::add_effect({
		parent_id	=> $parent, 
		type		=> $code, 
		values		=> $values,
	});
	if($id)
	{
		my $i = 	Audio::Nama::effect_index($code);
		my $iname = $Audio::Nama::fx_cache->{registry}->[$i]->{name};
		my $pi = 	Audio::Nama::effect_index(Audio::Nama::type($parent));
		my $pname = $Audio::Nama::fx_cache->{registry}->[$pi]->{name};
		print "\nAdded $id ($iname) to $parent ($pname)\n\n";
	}
	1;
}
add_effect: _add_effect effect value(s?) {
	my $code = $item{effect};
	my $values = $item{"value(s?)"};
	print(qq{$code: unknown effect. Try "find_effect keyword(s)\n}), return 1
		unless Audio::Nama::effect_index($code);
	my $args = {
		track  => $Audio::Nama::this_track, 
		type   => Audio::Nama::full_effect_code($code),
		values => $values
	};
	my $fader = $Audio::Nama::this_track->pan || $Audio::Nama::this_track->vol; 
	$args->{before} = $fader if $fader;
 	my $id = Audio::Nama::add_effect($args);
	if ($id)
	{
		my $i = Audio::Nama::effect_index($code);
		my $iname = $Audio::Nama::fx_cache->{registry}->[$i]->{name};
		print "\nAdded $id ($iname)\n\n";
		$Audio::Nama::this_op = $id;
	}
 	1;
}
append_effect: _append_effect effect value(s?) {
	my $code = $item{effect};
	my $values = $item{"value(s?)"};
	print(qq{$code: unknown effect. Try "find_effect keyword(s)\n}), return 1
		unless Audio::Nama::effect_index($code);
	my $args = {
		track  => $Audio::Nama::this_track, 
		type   => Audio::Nama::full_effect_code($code),
		values => $values
	};
 	my $id = Audio::Nama::add_effect($args);
	if ($id)
	{
		my $i = Audio::Nama::effect_index($code);
		my $iname = $Audio::Nama::fx_cache->{registry}->[$i]->{name};
		print "\nAdded $id ($iname)\n\n";
		$Audio::Nama::this_op = $id;
	}
 	1;
}
insert_effect: _insert_effect before effect value(s?) {
	my $before = $item{before};
	my $code = $item{effect};
	my $values = $item{"value(s?)"};
	print join ", ", @{$values} if $values;
	my $id = Audio::Nama::add_effect({
		before 	=> $before, 
		type	=> $code, 
		values	=> $values,
	});
	if($id)
	{
		my $i = Audio::Nama::effect_index($code);
		my $iname = $Audio::Nama::fx_cache->{registry}->[$i]->{name};
		my $bi = 	Audio::Nama::effect_index(Audio::Nama::type($before));
		my $bname = $Audio::Nama::fx_cache->{registry}->[$bi]->{name};
 		print "\nInserted $id ($iname) before $before ($bname)\n\n";
		$Audio::Nama::this_op = $id;
	}
	1;}
before: op_id
parent: op_id
modify_effect: _modify_effect parameter(s /,/) value {
	print("current effect is undefined, skipping\n"), return 1 if ! $Audio::Nama::this_op;
	Audio::Nama::modify_multiple_effects( 
		[$Audio::Nama::this_op], 
		$item{'parameter(s)'},
		undef,
		$item{value});
	print Audio::Nama::show_effect($Audio::Nama::this_op)
}
modify_effect: _modify_effect parameter(s /,/) sign value {
	print("current effect is undefined, skipping\n"), return 1 if ! $Audio::Nama::this_op;
	Audio::Nama::modify_multiple_effects( [$Audio::Nama::this_op], @item{qw(parameter(s) sign value)});
	print Audio::Nama::show_effect($Audio::Nama::this_op)
}
modify_effect: _modify_effect op_id(s /,/) parameter(s /,/) value {
	Audio::Nama::modify_multiple_effects( @item{qw(op_id(s) parameter(s) sign value)});
	Audio::Nama::pager(Audio::Nama::show_effect(@{ $item{'op_id(s)'} }))
}
modify_effect: _modify_effect op_id(s /,/) parameter(s /,/) sign value {
	Audio::Nama::modify_multiple_effects( @item{qw(op_id(s) parameter(s) sign value)});
	Audio::Nama::pager(Audio::Nama::show_effect(@{ $item{'op_id(s)'} }));
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
		map{ Audio::Nama::show_effect($_) } 
		grep{ Audio::Nama::fx($_) }
		@{ $item{'op_id(s)'}};
	$Audio::Nama::this_op = $item{'op_id(s)'}->[-1];
	Audio::Nama::pager(@lines); 1
}
show_effect: _show_effect {
	print("current effect is undefined, skipping\n"), return 1 if ! $Audio::Nama::this_op;
	print Audio::Nama::show_effect($Audio::Nama::this_op);
	1;
}
list_effects: _list_effects { Audio::Nama::pager(Audio::Nama::list_effects()); 1}
new_bunch: _new_bunch ident(s) { Audio::Nama::bunch( @{$item{'ident(s)'}}); 1}
list_bunches: _list_bunches { Audio::Nama::bunch(); 1}
remove_bunches: _remove_bunches ident(s) { 
 	map{ delete $Audio::Nama::gui->{_project_name}->{bunch}->{$_} } @{$item{'ident(s)'}}; 1}
add_to_bunch: _add_to_bunch ident(s) { Audio::Nama::add_to_bunch( @{$item{'ident(s)'}});1 }
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
	$Audio::Nama::config->{memoize} = 1;
	memoize('candidates'); 1
}
unmemoize: _unmemoize {
	package Audio::Nama::Wav;
	$Audio::Nama::config->{memoize} = 0;
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
	my @history = $Audio::Nama::text->{term}->GetHistory;
	my %seen;
	map { print "$_\n" unless $seen{$_}; $seen{$_}++ } @history
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
add_insert: _add_insert 'local' {
	Audio::Nama::Insert::add_insert( $Audio::Nama::this_track,'postfader_insert');
	1;
}
add_insert: _add_insert prepost send_id return_id(?) {
	my $return_id = $item{'return_id(?)'}->[0];
	my $send_id = $item{send_id};
	Audio::Nama::Insert::add_insert($Audio::Nama::this_track, "$item{prepost}fader_insert",$send_id, $return_id);
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
	$i->set_wetness($p);
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
	my $name = $item{ident};
	my @ops = @{$item{'op_id(s?)'}};
	scalar @ops or @ops = $Audio::Nama::this_track->fancy_ops;
	@ops = Audio::Nama::expanded_ops_list(@ops);
	my ($old_entry) = Audio::Nama::EffectChain::find(user => 1, name => $name);
	my @options;
	push(@options, 'n' , $old_entry->n) if $old_entry;
	Audio::Nama::EffectChain->new(
		user   => 1,
		global => 1,
		name   => $item{ident},
		ops_list => [ @ops ],
		@options,
	);
	1;
}
add_effect_chain: _add_effect_chain ident {
	Audio::Nama::EffectChain::find(
		unique => 1, 
		user   => 1, 
		name   => $item{ident}
	)->add($Audio::Nama::this_track);
	1;
}
delete_effect_chain: _delete_effect_chain ident(s) {
	map{ 
		Audio::Nama::EffectChain::find(
			unique => 1, 
			user   => 1,
			name   => $_
		)->destroy() 
	} @{ $item{'ident(s)'} };
	1;
}
find_effect_chains: _find_effect_chains ident(s?) 
{
	my @args;
	push @args, @{ $item{'ident(s)'} } if $item{'ident(s)'};
	Audio::Nama::pager(map{$_->dump} Audio::Nama::EffectChain::find(@args));
}
find_user_effect_chains: _find_user_effect_chains ident(s?)
{
	my @args = ('user' , 1);
	push @args, @{ $item{'ident(s)'} } if $item{'ident(s)'};
	(scalar @args) % 2 == 0 
		or print("odd number of arguments\n@args\n"), return 0;
	Audio::Nama::pager( map{ $_->summary} Audio::Nama::EffectChain::find(@args)  );
	1;
}
bypass_effects:   _bypass_effects op_id(s) { 
	my $arr_ref = $item{'op_id(s)'};
	return unless (ref $arr_ref) =~ /ARRAY/  and scalar @{$arr_ref};
	my @illegal = grep { ! Audio::Nama::fx($_) } @$arr_ref;
	print("@illegal: non-existing effect(s), aborting."), return 0 if @illegal;
 	print "track ",$Audio::Nama::this_track->name,", bypassing effects:\n";
	print Audio::Nama::named_effects_list(@$arr_ref);
	Audio::Nama::bypass_effects($Audio::Nama::this_track,@$arr_ref);
	$Audio::Nama::this_op = $arr_ref->[0] if scalar @$arr_ref == 1;
}
bypass_effects: _bypass_effects 'all' { 
	print "track ",$Audio::Nama::this_track->name,", bypassing all effects (except vol/pan)\n";
	Audio::Nama::bypass_effects($Audio::Nama::this_track, $Audio::Nama::this_track->fancy_ops)
		if $Audio::Nama::this_track->fancy_ops;
	1; 
}
bypass_effects: _bypass_effects { 
	print("current effect is undefined, skipping\n"), return 1 if ! $Audio::Nama::this_op;
 	print "track ",$Audio::Nama::this_track->name,", bypassing effects:\n"; 
	print Audio::Nama::named_effects_list($Audio::Nama::this_op);
 	Audio::Nama::bypass_effects($Audio::Nama::this_track, $Audio::Nama::this_op);  
 	1; 
}
bring_back_effects:   _bring_back_effects end { 
	print("current effect is undefined, skipping\n"), return 1 if ! $Audio::Nama::this_op;
	print "restoring effects:\n";
	print Audio::Nama::named_effects_list($Audio::Nama::this_op);
	Audio::Nama::restore_effects( $Audio::Nama::this_track, $Audio::Nama::this_op);
}
bring_back_effects:   _bring_back_effects op_id(s) { 
	my $arr_ref = $item{'op_id(s)'};
	return unless (ref $arr_ref) =~ /ARRAY/  and scalar @{$arr_ref};
	my @illegal = grep { ! Audio::Nama::fx($_) } @$arr_ref;
	print("@illegal: non-existing effect(s), aborting."), return 0 if @illegal;
	print "restoring effects:\n";
	print Audio::Nama::named_effects_list(@$arr_ref);
	Audio::Nama::restore_effects($Audio::Nama::this_track,@$arr_ref);
	$Audio::Nama::this_op = $arr_ref->[0] if scalar @$arr_ref == 1;
}
bring_back_effects:   _bring_back_effects 'all' { 
	print "restoring all effects\n";
	Audio::Nama::restore_effects( $Audio::Nama::this_track, $Audio::Nama::this_track->fancy_ops);
}
effect_chain_id: effect_chain_id_pair(s) {
 		die " i found an effect chain id";
  		my @pairs = @{$item{'effect_chain_id_pair(s)'}};
  		my @found = Audio::Nama::EffectChain::find(@pairs);
  		@found and 
  			print join " ", 
  			"found effect chain(s):",
  			map{ ('name:', $_->name, 'n', $_->n )} @found;
}
effect_chain_id_pair: fxc_key fxc_val { return @$item{fxc_key fxc_val} }
fxc_key: 'n'|                
		'ops_list'|
        'ops_dat'|
		'inserts_data'|
		'name'|
		'id'|
		'project'|
		'global'|
		'profile'|
		'user'|
		'system'|
		'track_name'|
		'track_version'|
		'track_cache'|
		'bypass'
fxc_val: shellish
this_track_op_id: op_id(s) { 
	my %ops = map{ $_ => 1 } @{$Audio::Nama::this_track->ops};
	my @ids = @{$item{'op_id(s)'}};
	my @belonging 	= grep {   $ops{$_} } @ids;
	my @alien 		= grep { ! $ops{$_} } @ids;
	@alien and print("@alien: don't belong to track ",$Audio::Nama::this_track->name, "skipping.\n"); 
	@belonging	
}
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
		unless Audio::Nama::EffectChain::find(profile => $item{ident});
	$item{ident}
}
new_effect_profile: _new_effect_profile bunch_name effect_profile_name {
	Audio::Nama::new_effect_profile($item{bunch_name}, $item{effect_profile_name}); 1 }
delete_effect_profile: _delete_effect_profile existing_effect_profile_name {
	Audio::Nama::delete_effect_profile($item{existing_effect_profile_name}); 1 }
apply_effect_profile: _apply_effect_profile existing_effect_profile_name {
	Audio::Nama::apply_effect_profile($item{effect_profile_name}); 1 }
list_effect_profiles: _list_effect_profiles ident(?) {
	my $name;
	$name = $item{'ident(?)'}->[-1] if $item{'ident(?)'};
	$name ||= 1;
	my @output = 
		map
		{ 	
			$name = $_->profile;
			$_->track_name;
		} Audio::Nama::EffectChain::find(profile => $name);
	if( @output )
	{ Audio::Nama::pager( "\nname: $name\ntracks: ", join " ",@output) }
	else { print "no match\n" }
	1;
}
show_effect_profiles: _show_effect_profiles ident(?) {
	my $name;
	$name = $item{'ident(?)'}->[-1] if $item{'ident(?)'};
	$name ||= 1;
	my $old_profile_name;
	my $profile_name;
	my @output = 
		grep{ ! /index:/ }
		map
		{ 	
			my @out;
			my $profile_name = $_->profile;
			if ( $profile_name ne $old_profile_name )
			{
			 	push @out, "name: $profile_name\n";
				$old_profile_name = $profile_name 
			}
			push @out, $_->summary;
			@out
		} Audio::Nama::EffectChain::find(profile => $name);
	if( @output )
	{ Audio::Nama::pager( @output); }
	else { print "no match\n" }
	1;
}
full_effect_profiles: _full_effect_profiles ident(?) {
	my $name;
	$name = $item{'ident(?)'}->[-1] if $item{'ident(?)'};
	$name ||= 1;
	my @output = map{ $_->dump } Audio::Nama::EffectChain::find(profile => $name )  ;
	if( @output )
	{ Audio::Nama::pager( @output); }
	else { print "no match\n" }
	1;
}
do_script: _do_script shellish { Audio::Nama::do_script($item{shellish});1}
scan: _scan { print "scanning ", Audio::Nama::this_wav_dir(), "\n"; Audio::Nama::rememoize() }
add_fade: _add_fade in_or_out mark1 duration(?)
{ 	Audio::Nama::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					duration => $item{'duration(?)'}->[0] 
								|| $Audio::Nama::config->{engine_fade_default_length}, 
					relation => 'fade_from_mark',
					track => $Audio::Nama::this_track->name,
	); 
	++$Audio::Nama::setup->{changed};
}
add_fade: _add_fade in_or_out duration(?) mark1 
{ 	Audio::Nama::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					duration => $item{'duration(?)'}->[0] 
								|| $Audio::Nama::config->{engine_fade_default_length}, 
					track => $Audio::Nama::this_track->name,
					relation => 'fade_to_mark',
	);
	++$Audio::Nama::setup->{changed};
}
add_fade: _add_fade in_or_out mark1 mark2
{ 	Audio::Nama::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					mark2 => $item{mark2},
					track => $Audio::Nama::this_track->name,
	);
	++$Audio::Nama::setup->{changed};
}
in_or_out: 'in' | 'out'
duration: value
mark1: markname
mark2: markname
remove_fade: _remove_fade fade_index(s) { 
	my @i = @{ $item{'fade_index(s)'} };
	Audio::Nama::remove_fade($_) for (@i);
	$Audio::Nama::setup->{changed}++;
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
	$Audio::Nama::setup->{edit_points}->[0] = Audio::Nama::eval_iam('getpos'); 1}
set_rec_start_mark: _set_rec_start_mark {
	$Audio::Nama::setup->{edit_points}->[1] = Audio::Nama::eval_iam('getpos'); 1}
set_rec_end_mark: _set_rec_end_mark {
	$Audio::Nama::setup->{edit_points}->[2] = Audio::Nama::eval_iam('getpos'); 1}
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
	$Audio::Nama::setup->{runtime_limit} = $sign
		? eval "$Audio::Nama::setup->{audio_length} $sign $item{dd}"
		: $item{dd};
	print "Run time limit: ", Audio::Nama::heuristic_time($Audio::Nama::setup->{runtime_limit}), "\n"; 1;
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
view_waveform: _view_waveform { 
	my $viewer = 'mhwaveedit';
	if( `which $viewer` =~ m/\S/){ 
		my $cmd = join " ",
			$viewer,
			"--driver",
			$Audio::Nama::jack->{jackd_running} ? "jack" : "alsa",
			$Audio::Nama::this_track->full_path,
			"&";
		system($cmd) 
	}
	else { print "No waveform viewer available (need to install Mhwaveedit?)\n" }
}
edit_waveform: _edit_waveform { 
	if ( `which audacity` =~ m/\S/ ){  
		my $cmd = join " ",
			'audacity',
			$Audio::Nama::this_track->full_path,
			"&";
		my $old_pwd = Audio::Nama::getcwd();		
		chdir Audio::Nama::this_wav_dir();
		system($cmd);
		chdir $old_pwd;
	}
	else { print "No waveform editor available (need to install Audacity?)\n" }
	1;
}
rerecord: _rerecord { 
		scalar @{$Audio::Nama::setup->{_last_rec_tracks}} 
			?  print "Toggling previous recording tracks to REC\n"
			:  print "No tracks in REC list. Skipping.\n";
		map{ $_->set(rw => 'REC') } @{$Audio::Nama::setup->{_last_rec_tracks}}; 
		Audio::Nama::restore_preview_mode();
		1;
}
eager: _eager mode_string { $Audio::Nama::mode->{eager} = $item{mode_string} }
mode_string: 'off'    { 0 }
mode_string: 'doodle' 
mode_string: 'preview'
show_track_latency: _show_track_latency {
	my $node = $Audio::Nama::setup->{latency}->{track}->{$Audio::Nama::this_track->name};
	print Audio::Nama::yaml_out($node) if $node;
	1;
}
show_latency_all: _show_latency_all { 
	print Audio::Nama::yaml_out($Audio::Nama::setup->{latency}) if $Audio::Nama::setup->{latency};
	1;
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
command: restart_ecasound
command: preview
command: doodle
command: mixdown
command: mixplay
command: mixoff
command: automix
command: master_on
command: master_off
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
command: show_track_latency
command: show_latency_all
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
command: arm_start
command: connect
command: disconnect
command: show_chain_setup
command: loop_enable
command: loop_disable
command: add_controller
command: add_effect
command: append_effect
command: insert_effect
command: modify_effect
command: remove_effect
command: position_effect
command: show_effect
command: list_effects
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
command: find_effect_chains
command: find_user_effect_chains
command: bypass_effects
command: bring_back_effects
command: new_effect_profile
command: apply_effect_profile
command: delete_effect_profile
command: list_effect_profiles
command: show_effect_profiles
command: full_effect_profiles
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
command: view_waveform
command: edit_waveform
command: rerecord
command: eager
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
_restart_ecasound: /restart_ecasound\b/
_preview: /preview\b/
_doodle: /doodle\b/
_mixdown: /mixdown\b/ | /mxd\b/
_mixplay: /mixplay\b/ | /mxp\b/
_mixoff: /mixoff\b/ | /mxo\b/
_automix: /automix\b/
_master_on: /master_on\b/ | /mr\b/
_master_off: /master_off\b/ | /mro\b/
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
_show_tracks: /show_tracks\b/ | /lt\b/ | /show\b/
_show_tracks_all: /show_tracks_all\b/ | /sha\b/ | /showa\b/
_show_bus_tracks: /show_bus_tracks\b/ | /shb\b/
_show_track: /show_track\b/ | /sh\b/
_show_mode: /show_mode\b/ | /shm\b/
_show_track_latency: /show_track_latency\b/ | /shl\b/
_show_latency_all: /show_latency_all\b/ | /shla\b/
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
_arm_start: /arm_start\b/ | /arms\b/
_connect: /connect\b/ | /con\b/
_disconnect: /disconnect\b/ | /dcon\b/
_show_chain_setup: /show_chain_setup\b/ | /chains\b/
_loop_enable: /loop_enable\b/ | /loop\b/
_loop_disable: /loop_disable\b/ | /noloop\b/ | /nl\b/
_add_controller: /add_controller\b/ | /acl\b/
_add_effect: /add_effect\b/ | /afx\b/
_append_effect: /append_effect\b/ | /apfx\b/
_insert_effect: /insert_effect\b/ | /ifx\b/
_modify_effect: /modify_effect\b/ | /mfx\b/ | /modify_controller\b/ | /mcl\b/
_remove_effect: /remove_effect\b/ | /rfx\b/ | /remove_controller\b/ | /rcl\b/
_position_effect: /position_effect\b/ | /pfx\b/
_show_effect: /show_effect\b/ | /sfx\b/
_list_effects: /list_effects\b/ | /lfx\b/
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
_find_effect_chains: /find_effect_chains\b/ | /fec\b/
_find_user_effect_chains: /find_user_effect_chains\b/ | /fuc\b/
_bypass_effects: /bypass_effects\b/ | /bypass\b/ | /bfx\b/
_bring_back_effects: /bring_back_effects\b/ | /restore_effects\b/ | /bbfx\b/
_new_effect_profile: /new_effect_profile\b/ | /nep\b/
_apply_effect_profile: /apply_effect_profile\b/ | /aep\b/
_delete_effect_profile: /delete_effect_profile\b/ | /dep\b/
_list_effect_profiles: /list_effect_profiles\b/ | /lep\b/
_show_effect_profiles: /show_effect_profiles\b/ | /sepr\b/
_full_effect_profiles: /full_effect_profiles\b/ | /fep\b/
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
_view_waveform: /view_waveform\b/ | /wview\b/
_edit_waveform: /edit_waveform\b/ | /wedit\b/
_rerecord: /rerecord\b/ | /rerec\b/
_eager: /eager\b/
@@ chain_op_hints_yml
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
@@ default_namarc
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
    hardware_latency: 0
  multi:
    ecasound_id: alsa,ice1712
    input_format: s32_le,12,frequency
    output_format: s32_le,10,frequency
    hardware_latency: 0
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

sample_rate: frequency

# globals for our chain setups

ecasound_globals_general: -z:mixmode,sum
ecasound_globals_realtime: -z:db,100000 -z:nointbuf 
ecasound_globals_nonrealtime: -z:nodb -z:intbuf
ecasound_buffersize_realtime: 256
ecasound_buffersize_nonrealtime: 1024

# ecasound_tcp_port: 2868  

# WAVs recorded at the same time get the same numeric suffix

use_group_numbering: 1

# Enable pressing SPACE to start/stop transport (in terminal, cursor in column 1)

press_space_to_start_transport: 1

# commands to execute each time a project is loaded

execute_on_project_load: ~

volume_control_operator: eadb # must be 'ea' or 'eadb'

# beep PC speaker on command error

# beep_command: beep -f 350 -l 700

# effects for use in mastering mode

eq: Parametric1 1 0 0 40 1 0 0 200 1 0 0 600 1 0 0 3300 1 0

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
#
# eager_mode: doodle | preview

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


@@ custom_pl
### custom.pl - Nama user customization file

# See notes at end

##  Prompt section - replaces default user prompt

prompt =>  
	q{
	"nama [". ($this_bus eq 'Main' ? '': "$this_bus/").  
		($this_track ? $this_track->name : '') . "] > "
	},


##  Aliases section - shortcuts to any Nama or user-defined commands

aliases => 
	{
		mbs => 'move_to_bus',
		pcv => 'promote_current_version',
		hi => 'greet',
		djp => 'disable_jack_polling',
	},

fxshortcuts => 
	{
		foo => 'ea'
	},


## Commands section - user defined commands

commands => 
	{
			
		disable_jack_polling => 
			q{
				$engine->{events}->{poll_jack} = undef
			},
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

@@ fake_jack_lsp
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

@@ fake_lv2_register
1. Calf Compressor
	-elv2:http://calf.sourceforge.net/plugins/Compressor,'Threshold','Ratio','
... Attack','Release','Makeup Gain','Knee','Detection','Stereo
... Link','A-weighting','Compression','Peak Output','0dB','Bypass'
2. Calf Filter
	-elv2:http://calf.sourceforge.net/plugins/Filter,'Frequency','Resonance','
... Mode','Inertia'
3. Calf Filterclavier
	-elv2:http://calf.sourceforge.net/plugins/Filterclavier,'Transpose','Detun
... e','Max. Resonance','Mode','Portamento time'
4. Calf Flanger
	-elv2:http://calf.sourceforge.net/plugins/Flanger,'Minimum
... delay','Modulation depth','Modulation rate','Feedback','Stereo
... phase','Reset','Amount','Dry Amount'
5. Calf Monosynth
	-elv2:http://calf.sourceforge.net/plugins/Monosynth,'Osc1 Wave','Osc2
... Wave','O1<>2 Detune','Osc 2 transpose','Phase mode','O1<>2
... Mix','Filter','Cutoff','Resonance','Separation','Env->Cutoff','Env->Res'
... ,'Env->Amp','Attack','Decay','Sustain','Release','Key Follow','Legato
... Mode','Portamento','Vel->Filter','Vel->Amp','Volume','PBend Range'
6. Calf MultiChorus
	-elv2:http://calf.sourceforge.net/plugins/MultiChorus,'Minimum
... delay','Modulation depth','Modulation rate','Stereo
... phase','Voices','Inter-voice phase','Amount','Dry Amount','Center Frq
... 1','Center Frq 2','Q'
7. Calf Phaser
	-elv2:http://calf.sourceforge.net/plugins/Phaser,'Center
... Freq','Modulation depth','Modulation rate','Feedback','#
... Stages','Stereo phase','Reset','Amount','Dry Amount'
8. Calf Reverb
	-elv2:http://calf.sourceforge.net/plugins/Reverb,'Decay time','High Frq
... Damp','Room size','Diffusion','Wet Amount','Dry Amount','Pre
... Delay','Bass Cut','Treble Cut'
9. Calf Rotary Speaker
	-elv2:http://calf.sourceforge.net/plugins/RotarySpeaker,'Speed Mode','Tap
... Spacing','Tap Offset','Mod Depth','Treble Motor','Bass Motor','Mic
... Distance','Reflection'
10. Calf Vintage Delay
	-elv2:http://calf.sourceforge.net/plugins/VintageDelay,'Tempo','Subdivide'
... ,'Time L','Time R','Feedback','Amount','Mix mode','Medium','Dry Amount'
11. IR
	-elv2:http://factorial.hu/plugins/lv2/ir,'Reverse
... IR','Predelay','Attack','Attack
... time','Envelope','Length','Stretch','Stereo width in','Stereo width
... IR','Autogain','Dry','Dry gain','Wet','Wet
... gain','FileHash0','FileHash1','FileHash2','Dry L meter','Dry R
... meter','Wet L meter','Wet R meter','Latency'
12. Aliasing
	-elv2:http://plugin.org.uk/swh-plugins/alias,'Aliasing level'
13. Allpass delay line, cubic spline interpolation
	-elv2:http://plugin.org.uk/swh-plugins/allpass_c,'Max Delay (s)','Delay
... Time (s)','Decay Time (s)'
14. Allpass delay line, linear interpolation
	-elv2:http://plugin.org.uk/swh-plugins/allpass_l,'Max Delay (s)','Delay
... Time (s)','Decay Time (s)'
15. Allpass delay line, noninterpolating
	-elv2:http://plugin.org.uk/swh-plugins/allpass_n,'Max Delay (s)','Delay
... Time (s)','Decay Time (s)'
16. AM pitchshifter
	-elv2:http://plugin.org.uk/swh-plugins/amPitchshift,'Pitch shift','Buffer
... size','latency'
17. Simple amplifier
	-elv2:http://plugin.org.uk/swh-plugins/amp,'Amps gain (dB)'
18. Analogue Oscillator
	-elv2:http://plugin.org.uk/swh-plugins/analogueOsc,'Waveform (1=sin,
... 2=tri, 3=squ, 4=saw)','Frequency (Hz)','Warmth','Instability'
19. Artificial latency
	-elv2:http://plugin.org.uk/swh-plugins/artificialLatency,'Delay
... (ms)','latency'
20. Auto phaser
	-elv2:http://plugin.org.uk/swh-plugins/autoPhaser,'Attack time
... (s)','Decay time (s)','Modulation depth','Feedback','Spread (octaves)'
21. Glame Bandpass Analog Filter
	-elv2:http://plugin.org.uk/swh-plugins/bandpass_a_iir,'Center Frequency
... (Hz)','Bandwidth (Hz)'
22. Glame Bandpass Filter
	-elv2:http://plugin.org.uk/swh-plugins/bandpass_iir,'Center Frequency
... (Hz)','Bandwidth (Hz)','Stages(2 poles per stage)'
23. Bode frequency shifter
	-elv2:http://plugin.org.uk/swh-plugins/bodeShifter,'Frequency
... shift','latency'
24. Bode frequency shifter (CV)
	-elv2:http://plugin.org.uk/swh-plugins/bodeShifterCV,'Base shift','Mix
... (-1=down, +1=up)','CV Attenuation','latency'
25. GLAME Butterworth Highpass
	-elv2:http://plugin.org.uk/swh-plugins/butthigh_iir,'Cutoff Frequency
... (Hz)','Resonance'
26. GLAME Butterworth Lowpass
	-elv2:http://plugin.org.uk/swh-plugins/buttlow_iir,'Cutoff Frequency
... (Hz)','Resonance'
27. Glame Butterworth X-over Filter
	-elv2:http://plugin.org.uk/swh-plugins/bwxover_iir,'Cutoff Frequency
... (Hz)','Resonance'
28. Chebyshev distortion
	-elv2:http://plugin.org.uk/swh-plugins/chebstortion,'Distortion'
29. Comb Filter
	-elv2:http://plugin.org.uk/swh-plugins/comb,'Band separation
... (Hz)','Feedback'
30. Comb Splitter
	-elv2:http://plugin.org.uk/swh-plugins/combSplitter,'Band separation (Hz)'
31. Comb delay line, cubic spline interpolation
	-elv2:http://plugin.org.uk/swh-plugins/comb_c,'Max Delay (s)','Delay Time
... (s)','Decay Time (s)'
32. Comb delay line, linear interpolation
	-elv2:http://plugin.org.uk/swh-plugins/comb_l,'Max Delay (s)','Delay Time
... (s)','Decay Time (s)'
33. Comb delay line, noninterpolating
	-elv2:http://plugin.org.uk/swh-plugins/comb_n,'Max Delay (s)','Delay Time
... (s)','Decay Time (s)'
34. Constant Signal Generator
	-elv2:http://plugin.org.uk/swh-plugins/const,'Signal amplitude'
35. Crossover distortion
	-elv2:http://plugin.org.uk/swh-plugins/crossoverDist,'Crossover
... amplitude','Smoothing'
36. DC Offset Remover
	-elv2:http://plugin.org.uk/swh-plugins/dcRemove,
37. Exponential signal decay
	-elv2:http://plugin.org.uk/swh-plugins/decay,'Decay Time (s)'
38. Decimator
	-elv2:http://plugin.org.uk/swh-plugins/decimator,'Bit depth','Sample rate
... (Hz)'
39. Declipper
	-elv2:http://plugin.org.uk/swh-plugins/declip,
40. Simple delay line, cubic spline interpolation
	-elv2:http://plugin.org.uk/swh-plugins/delay_c,'Max Delay (s)','Delay
... Time (s)'
41. Simple delay line, linear interpolation
	-elv2:http://plugin.org.uk/swh-plugins/delay_l,'Max Delay (s)','Delay
... Time (s)'
42. Simple delay line, noninterpolating
	-elv2:http://plugin.org.uk/swh-plugins/delay_n,'Max Delay (s)','Delay
... Time (s)'
43. Delayorama
	-elv2:http://plugin.org.uk/swh-plugins/delayorama,'Random seed','Input
... gain (dB)','Feedback (%)','Number of taps','First delay (s)','Delay
... range (s)','Delay change','Delay random (%)','Amplitude
... change','Amplitude random (%)','Dry/wet mix'
44. Diode Processor
	-elv2:http://plugin.org.uk/swh-plugins/diode,'Mode (0 for none, 1 for
... half wave, 2 for full wave)'
45. Audio Divider (Suboctave Generator)
	-elv2:http://plugin.org.uk/swh-plugins/divider,'Denominator'
46. DJ flanger
	-elv2:http://plugin.org.uk/swh-plugins/djFlanger,'LFO sync','LFO period
... (s)','LFO depth (ms)','Feedback (%)'
47. DJ EQ
	-elv2:http://plugin.org.uk/swh-plugins/dj_eq,'Lo gain (dB)','Mid gain
... (dB)','Hi gain (dB)','latency'
48. DJ EQ (mono)
	-elv2:http://plugin.org.uk/swh-plugins/dj_eq_mono,'Lo gain (dB)','Mid
... gain (dB)','Hi gain (dB)','latency'
49. Dyson compressor
	-elv2:http://plugin.org.uk/swh-plugins/dysonCompress,'Peak limit
... (dB)','Release time (s)','Fast compression ratio','Compression ratio'
50. Fractionally Addressed Delay Line
	-elv2:http://plugin.org.uk/swh-plugins/fadDelay,'Delay
... (seconds)','Feedback (dB)'
51. Fast Lookahead limiter
	-elv2:http://plugin.org.uk/swh-plugins/fastLookaheadLimiter,'Input gain
... (dB)','Limit (dB)','Release time (s)','Attenuation (dB)','latency'
52. Flanger
	-elv2:http://plugin.org.uk/swh-plugins/flanger,'Delay base (ms)','Max
... slowdown (ms)','LFO frequency (Hz)','Feedback'
53. FM Oscillator
	-elv2:http://plugin.org.uk/swh-plugins/fmOsc,'Waveform (1=sin, 2=tri,
... 3=squ, 4=saw)'
54. Foldover distortion
	-elv2:http://plugin.org.uk/swh-plugins/foldover,'Drive','Skew'
55. 4 x 4 pole allpass
	-elv2:http://plugin.org.uk/swh-plugins/fourByFourPole,'Frequency
... 1','Feedback 1','Frequency 2','Feedback 2','Frequency 3','Feedback
... 3','Frequency 4','Feedback 4'
56. Fast overdrive
	-elv2:http://plugin.org.uk/swh-plugins/foverdrive,'Drive level'
57. Frequency tracker
	-elv2:http://plugin.org.uk/swh-plugins/freqTracker,'Tracking speed'
58. Gate
	-elv2:http://plugin.org.uk/swh-plugins/gate,'LF key filter (Hz)','HF key
... filter (Hz)','Threshold (dB)','Attack (ms)','Hold (ms)','Decay
... (ms)','Range (dB)','Output select (-1 = key listen, 0 = gate, 1 =
... bypass)','Key level (dB)','Gate state'
59. Giant flange
	-elv2:http://plugin.org.uk/swh-plugins/giantFlange,'Double delay','LFO
... frequency 1 (Hz)','Delay 1 range (s)','LFO frequency 2 (Hz)','Delay 2
... range (s)','Feedback','Dry/Wet level'
60. Gong model
	-elv2:http://plugin.org.uk/swh-plugins/gong,'Inner damping','Outer
... damping','Mic position','Inner size 1','Inner stiffness 1 +','Inner
... stiffness 1 -','Inner size 2','Inner stiffness 2 +','Inner stiffness 2
... -','Inner size 3','Inner stiffness 3 +','Inner stiffness 3 -','Inner
... size 4','Inner stiffness 4 +','Inner stiffness 4 -','Outer size
... 1','Outer stiffness 1 +','Outer stiffness 1 -','Outer size 2','Outer
... stiffness 2 +','Outer stiffness 2 -','Outer size 3','Outer stiffness 3
... +','Outer stiffness 3 -','Outer size 4','Outer stiffness 4 +','Outer
... stiffness 4 -'
61. Gong beater
	-elv2:http://plugin.org.uk/swh-plugins/gongBeater,'Impulse gain
... (dB)','Strike gain (dB)','Strike duration (s)'
62. GVerb
	-elv2:http://plugin.org.uk/swh-plugins/gverb,'Roomsize (m)','Reverb time
... (s)','Damping','Input bandwidth','Dry signal level (dB)','Early
... reflection level (dB)','Tail level (dB)'
63. Hard Limiter
	-elv2:http://plugin.org.uk/swh-plugins/hardLimiter,'dB limit','Wet
... level','Residue level'
64. Harmonic generator
	-elv2:http://plugin.org.uk/swh-plugins/harmonicGen,'Fundamental
... magnitude','2nd harmonic magnitude','3rd harmonic magnitude','4th
... harmonic magnitude','5th harmonic magnitude','6th harmonic
... magnitude','7th harmonic magnitude','8th harmonic magnitude','9th
... harmonic magnitude','10th harmonic magnitude'
65. Hermes Filter
	-elv2:http://plugin.org.uk/swh-plugins/hermesFilter,'LFO1 freq
... (Hz)','LFO1 wave (0 = sin, 1 = tri, 2 = saw, 3 = squ, 4 = s&h)','LFO2
... freq (Hz)','LFO2 wave (0 = sin, 1 = tri, 2 = saw, 3 = squ, 4 =
... s&h)','Osc1 freq (Hz)','Osc1 wave (0 = sin, 1 = tri, 2 = saw, 3 = squ,
... 4 = noise)','Osc2 freq (Hz)','Osc2 wave (0 = sin, 1 = tri, 2 = saw, 3 =
... squ, 4 = noise)','Ringmod 1 depth (0=none, 1=AM, 2=RM)','Ringmod 2
... depth (0=none, 1=AM, 2=RM)','Ringmod 3 depth (0=none, 1=AM,
... 2=RM)','Osc1 gain (dB)','RM1 gain (dB)','Osc2 gain (dB)','RM2 gain
... (dB)','Input gain (dB)','RM3 gain (dB)','Xover lower freq','Xover upper
... freq','Dist1 drive','Dist2 drive','Dist3 drive','Filt1 type (0=none,
... 1=LP, 2=HP, 3=BP, 4=BR, 5=AP)','Filt1 freq','Filt1 q','Filt1
... resonance','Filt1 LFO1 level','Filt1 LFO2 level','Filt2 type (0=none,
... 1=LP, 2=HP, 3=BP, 4=BR, 5=AP)','Filt2 freq','Filt2 q','Filt2
... resonance','Filt2 LFO1 level','Filt2 LFO2 level','Filt3 type (0=none,
... 1=LP, 2=HP, 3=BP, 4=BR, 5=AP)','Filt3 freq','Filt3 q','Filt3
... resonance','Filt3 LFO1 level','Filt3 LFO2 level','Delay1 length
... (s)','Delay1 feedback','Delay1 wetness','Delay2 length (s)','Delay2
... feedback','Delay2 wetness','Delay3 length (s)','Delay3
... feedback','Delay3 wetness','Band 1 gain (dB)','Band 2 gain (dB)','Band
... 3 gain (dB)'
66. Glame Highpass Filter
	-elv2:http://plugin.org.uk/swh-plugins/highpass_iir,'Cutoff
... Frequency','Stages(2 poles per stage)'
67. Hilbert transformer
	-elv2:http://plugin.org.uk/swh-plugins/hilbert,'latency'
68. Non-bandlimited single-sample impulses
	-elv2:http://plugin.org.uk/swh-plugins/impulse_fc,'Frequency (Hz)'
69. Inverter
	-elv2:http://plugin.org.uk/swh-plugins/inv,
70. Karaoke
	-elv2:http://plugin.org.uk/swh-plugins/karaoke,'Vocal volume (dB)'
71. L/C/R Delay
	-elv2:http://plugin.org.uk/swh-plugins/lcrDelay,'L delay (ms)','L
... level','C delay (ms)','C level','R delay (ms)','R
... level','Feedback','High damp (%)','Low damp (%)','Spread','Dry/Wet
... level'
72. LFO Phaser
	-elv2:http://plugin.org.uk/swh-plugins/lfoPhaser,'LFO rate (Hz)','LFO
... depth','Feedback','Spread (octaves)'
73. Lookahead limiter
	-elv2:http://plugin.org.uk/swh-plugins/lookaheadLimiter,'Limit
... (dB)','Lookahead delay','Attenuation (dB)','latency'
74. Lookahead limiter (fixed latency)
	-elv2:http://plugin.org.uk/swh-plugins/lookaheadLimiterConst,'Limit
... (dB)','Lookahead time (s)','Attenuation (dB)','latency'
75. Glame Lowpass Filter
	-elv2:http://plugin.org.uk/swh-plugins/lowpass_iir,'Cutoff
... Frequency','Stages(2 poles per stage)'
76. LS Filter
	-elv2:http://plugin.org.uk/swh-plugins/lsFilter,'Filter type (0=LP, 1=BP,
... 2=HP)','Cutoff frequency (Hz)','Resonance'
77. Matrix: MS to Stereo
	-elv2:http://plugin.org.uk/swh-plugins/matrixMSSt,'Width'
78. Matrix Spatialiser
	-elv2:http://plugin.org.uk/swh-plugins/matrixSpatialiser,'Width'
79. Matrix: Stereo to MS
	-elv2:http://plugin.org.uk/swh-plugins/matrixStMS,
80. Multiband EQ
	-elv2:http://plugin.org.uk/swh-plugins/mbeq,'50Hz gain (low
... shelving)','100Hz gain','156Hz gain','220Hz gain','311Hz gain','440Hz
... gain','622Hz gain','880Hz gain','1250Hz gain','1750Hz gain','2500Hz
... gain','3500Hz gain','5000Hz gain','10000Hz gain','20000Hz
... gain','latency'
81. Modulatable delay
	-elv2:http://plugin.org.uk/swh-plugins/modDelay,'Base delay (s)'
82. Multivoice Chorus
	-elv2:http://plugin.org.uk/swh-plugins/multivoiceChorus,'Number of
... voices','Delay base (ms)','Voice separation (ms)','Detune (%)','LFO
... frequency (Hz)','Output attenuation (dB)'
83. Higher Quality Pitch Scaler
	-elv2:http://plugin.org.uk/swh-plugins/pitchScaleHQ,'Pitch
... co-efficient','latency'
84. Plate reverb
	-elv2:http://plugin.org.uk/swh-plugins/plate,'Reverb
... time','Damping','Dry/wet mix'
85. Pointer cast distortion
	-elv2:http://plugin.org.uk/swh-plugins/pointerCastDistortion,'Effect
... cutoff freq (Hz)','Dry/wet mix'
86. Rate shifter
	-elv2:http://plugin.org.uk/swh-plugins/rateShifter,'Rate'
87. Retro Flanger
	-elv2:http://plugin.org.uk/swh-plugins/retroFlange,'Average stall
... (ms)','Flange frequency (Hz)'
88. Reverse Delay (5s max)
	-elv2:http://plugin.org.uk/swh-plugins/revdelay,'Delay Time (s)','Dry
... Level (dB)','Wet Level (dB)','Feedback','Crossfade samples'
89. Ringmod with LFO
	-elv2:http://plugin.org.uk/swh-plugins/ringmod_1i1o1l,'Modulation depth
... (0=none, 1=AM, 2=RM)','Frequency (Hz)','Sine level','Triangle
... level','Sawtooth level','Square level'
90. Ringmod with two inputs
	-elv2:http://plugin.org.uk/swh-plugins/ringmod_2i1o,'Modulation depth
... (0=none, 1=AM, 2=RM)'
91. Barry's Satan Maximiser
	-elv2:http://plugin.org.uk/swh-plugins/satanMaximiser,'Decay time
... (samples)','Knee point (dB)'
92. SC1
	-elv2:http://plugin.org.uk/swh-plugins/sc1,'Attack time (ms)','Release
... time (ms)','Threshold level (dB)','Ratio (1:n)','Knee radius
... (dB)','Makeup gain (dB)'
93. SC2
	-elv2:http://plugin.org.uk/swh-plugins/sc2,'Attack time (ms)','Release
... time (ms)','Threshold level (dB)','Ratio (1:n)','Knee radius
... (dB)','Makeup gain (dB)'
94. SC3
	-elv2:http://plugin.org.uk/swh-plugins/sc3,'Attack time (ms)','Release
... time (ms)','Threshold level (dB)','Ratio (1:n)','Knee radius
... (dB)','Makeup gain (dB)','Chain balance'
95. SC4
	-elv2:http://plugin.org.uk/swh-plugins/sc4,'RMS/peak','Attack time
... (ms)','Release time (ms)','Threshold level (dB)','Ratio (1:n)','Knee
... radius (dB)','Makeup gain (dB)','Amplitude (dB)','Gain reduction (dB)'
96. SE4
	-elv2:http://plugin.org.uk/swh-plugins/se4,'RMS/peak','Attack time
... (ms)','Release time (ms)','Threshold level (dB)','Ratio (1:n)','Knee
... radius (dB)','Attenuation (dB)','Amplitude (dB)','Gain expansion (dB)'
97. Wave shaper
	-elv2:http://plugin.org.uk/swh-plugins/shaper,'Waveshape'
98. Signal sifter
	-elv2:http://plugin.org.uk/swh-plugins/sifter,'Sift size'
99. Sine + cosine oscillator
	-elv2:http://plugin.org.uk/swh-plugins/sinCos,'Base frequency
... (Hz)','Pitch offset'
100. Single band parametric
	-elv2:http://plugin.org.uk/swh-plugins/singlePara,'Gain (dB)','Frequency
... (Hz)','Bandwidth (octaves)'
101. Sinus wavewrapper
	-elv2:http://plugin.org.uk/swh-plugins/sinusWavewrapper,'Wrap degree'
102. Smooth Decimator
	-elv2:http://plugin.org.uk/swh-plugins/smoothDecimate,'Resample
... rate','Smoothing'
103. Mono to Stereo splitter
	-elv2:http://plugin.org.uk/swh-plugins/split,
104. Surround matrix encoder
	-elv2:http://plugin.org.uk/swh-plugins/surroundEncoder,
105. State Variable Filter
	-elv2:http://plugin.org.uk/swh-plugins/svf,'Filter type (0=none, 1=LP,
... 2=HP, 3=BP, 4=BR, 5=AP)','Filter freq','Filter Q','Filter resonance'
106. Tape Delay Simulation
	-elv2:http://plugin.org.uk/swh-plugins/tapeDelay,'Tape speed (inches/sec,
... 1=normal)','Dry level (dB)','Tap 1 distance (inches)','Tap 1 level
... (dB)','Tap 2 distance (inches)','Tap 2 level (dB)','Tap 3 distance
... (inches)','Tap 3 level (dB)','Tap 4 distance (inches)','Tap 4 level
... (dB)'
107. Transient mangler
	-elv2:http://plugin.org.uk/swh-plugins/transient,'Attack speed','Sustain
... time'
108. Triple band parametric with shelves
	-elv2:http://plugin.org.uk/swh-plugins/triplePara,'Low-shelving gain
... (dB)','Low-shelving frequency (Hz)','Low-shelving slope','Band 1 gain
... (dB)','Band 1 frequency (Hz)','Band 1 bandwidth (octaves)','Band 2 gain
... (dB)','Band 2 frequency (Hz)','Band 2 bandwidth (octaves)','Band 3 gain
... (dB)','Band 3 frequency (Hz)','Band 3 bandwidth
... (octaves)','High-shelving gain (dB)','High-shelving frequency
... (Hz)','High-shelving slope'
109. Valve saturation
	-elv2:http://plugin.org.uk/swh-plugins/valve,'Distortion
... level','Distortion character'
110. Valve rectifier
	-elv2:http://plugin.org.uk/swh-plugins/valveRect,'Sag level','Distortion'
111. VyNil (Vinyl Effect)
	-elv2:http://plugin.org.uk/swh-plugins/vynil,'Year','RPM','Surface
... warping','Crackle','Wear'
112. Wave Terrain Oscillator
	-elv2:http://plugin.org.uk/swh-plugins/waveTerrain,
113. Crossfade
	-elv2:http://plugin.org.uk/swh-plugins/xfade,'Crossfade'
114. Crossfade (4 outs)
	-elv2:http://plugin.org.uk/swh-plugins/xfade4,'Crossfade'
115. z-1
	-elv2:http://plugin.org.uk/swh-plugins/zm1,
116. TalentedHack
	-elv2:urn:jeremy.salwen:plugins:talentedhack,'Mix','Pull To In
... Tune','Smooth Pitch','Formant Correction','Formant Warp','Jump To Midi
... Input','Pitch Correct Midi Out','Quantize LFO','LFO Amplitude','LFO
... Rate (Hz)','LFO Shape','LFO Symmetry','Concert A (Hz)','Detect
... A','Detect A#','Detect B','Detect C','Detect C#','Detect D','Detect
... D#','Detect E','Detect F','Detect F#','Detect G','Detect G#','Output
... A','Output A#','Output B','Output C','Output C#','Output D','Output
... D#','Output E','Output F','Output F#','Output G','Output G#','Latency'

@@ fake_jack_latency
system:capture_1
        port latency = 1024 frames
        port playback latency = [ 0 0 ] frames
        port capture latency = [ 1024 1024 ] frames
system:capture_2
        port latency = 1024 frames
        port playback latency = [ 0 0 ] frames
        port capture latency = [ 1024 1024 ] frames
system:playback_1
        port latency = 2048 frames
        port playback latency = [ 2048 2048 ] frames
        port capture latency = [ 0 0 ] frames
system:playback_2
        port latency = 2048 frames
        port playback latency = [ 2048 2048 ] frames
        port capture latency = [ 0 0 ] frames
LinuxSampler:capture_1
        port latency = 1024 frames
        port playback latency = [ 256 256 ] frames
        port capture latency = [ 512 1024 ] frames
LinuxSampler:capture_2
        port latency = 1024 frames
        port playback latency = [ 256 256 ] frames
        port capture latency = [ 256 1024 ] frames
LinuxSampler:playback_1
        port latency = 2048 frames
        port playback latency = [ 2048 2048 ] frames
        port capture latency = [ 512 512 ] frames
LinuxSampler:playback_2
        port latency = 2048 frames
        port playback latency = [ 2048 2048 ] frames
        port capture latency = [ 512 512 ] frames

@@ midish_commands
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

@@ default_palette_yml
---
gui:
  _nama_palette:
    Capture: '#f22c92f088d3'
    ClockBackground: '#998ca489b438'
    ClockForeground: '#000000000000'
    GroupBackground: '#998ca489b438'
    GroupForeground: '#000000000000'
    MarkArmed: '#d74a811f443f'
    Mixdown: '#bf67c5a1491f'
    MonBackground: '#9420a9aec871'
    MonForeground: Black
    Mute: '#a5a183828382'
    OffBackground: '#998ca489b438'
    OffForeground: Black
    Play: '#68d7aabf755c'
    RecBackground: '#d9156e866335'
    RecForeground: Black
    SendBackground: '#9ba79cbbcc8a'
    SendForeground: Black
    SourceBackground: '#f22c92f088d3'
    SourceForeground: Black
  _palette:
    ew:
      background: '#d915cc1bc3cf'
      foreground: black
    mw:
      activeBackground: '#81acc290d332'
      background: '#998ca489b438'
      foreground: black
...

__END__

=head1 NAME

Nama/Audio::Nama - an audio recording, mixing and editing application

=head1 DESCRIPTION

B<Nama> is an application for multitrack recording,
non-destructive editing, mixing and mastering using the
Ecasound audio engine developed by Kai Vehmanen.

Features include tracks, buses, effects, presets,
sends, inserts, marks and regions. Nama runs under JACK and
ALSA audio frameworks, automatically detects LADSPA plugins,
and supports Ladish Level 1 session handling.

Type C<man nama> for details.