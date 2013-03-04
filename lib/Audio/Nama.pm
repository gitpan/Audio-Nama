package Audio::Nama;
require 5.10.0;
use vars qw($VERSION);
$VERSION = "1.101";
use Modern::Perl;
#use Carp::Always;
no warnings qw(uninitialized syntax);
use autodie qw(:default);

########## External dependencies ##########

use Carp qw(carp cluck confess croak);
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
# use jacks;		# JACK server API

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

use Audio::Nama::AnalyseLV2;
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
use Audio::Nama::Mix ();
use Audio::Nama::Memoize ();

use Audio::Nama::EngineSetup ();
use Audio::Nama::EngineCleanup ();
use Audio::Nama::EffectsRegistry ();
use Audio::Nama::Effects ();
use Audio::Nama::EngineRun ();
use Audio::Nama::MuteSoloFade ();
use Audio::Nama::Jack ();

use Audio::Nama::Regions ();
use Audio::Nama::CacheTrack ();
use Audio::Nama::Bunch ();
use Audio::Nama::Wavinfo ();
use Audio::Nama::Midi ();
use Audio::Nama::Latency ();
use Audio::Nama::Log qw(logit loggit logpkg logsub initialize_logger);

sub main { 
	bootstrap_environment() ;
	process_command($config->{execute_on_project_load});
	reconfigure_engine();
	process_command($config->{opts}->{X});
	$ui->loop();
}

sub bootstrap_environment {
	definitions();
	process_command_line_options();
	start_logging();
	setup_grammar();
	initialize_interfaces();
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
  type: help 
  what: Display help on Nama commands.
  short: h
  parameters: [ <i_help_topic_index> | <s_help_topic_name> | <s_command_name> ]
  example: |
    help marks # display the help category marks and all commands containing marks
    help 6 # display help on the effects category
    help mfx # display help on modify_effect - shortcut mfx
help_effect:
  type: help
  what: Display detailed help on a LADSPA or LV2 effect or ask a note to consult the Ecasound manpage for Ecasound's internal effects. For LADSPA and LV2 effects use either the analyseplugin oder analyselv2.
  short: hfx he
  parameters: <s_label> | <i_unique_id>
  example: |
    help_effect 1970 # display help on Fons Adriaensen's parametric EQ (LADSPA)
    he etd # print a short message to consult Ecasound manpage, because etd is an internal effect
    hfx lv2-vocProc # display detailed help on the LV2 VocProc effect
find_effect:
  type: help
  what: Display one-line help for effects matching the search string(s).
  short: ffx fe
  parameters: <s_keyword1> [ <s_keyword2>... ]
  example: |
    find_effect compressor # List all effects containing compressor in their name or in parameters
    fe feedback # List all effects with feedback in their name or parameters (for example a delay with a tweakable feedback)
exit:
  type: general
  what: Exit Nama, saving settings (the current project).
  short: quit q
  parameters: none
memoize:
  type: general
  what: Enable WAV directory caching, so Nama won't have to scan the entire project folder for new fiels after every run.
  parameters: none
unmemoize:
  type: general
  what: Disable WAV directory caching.
  parameters: none
stop:
  type: transport
  what: Stop transport. Stop the engine, when recording or playing back.
  short: s
  parameters: none
  example: |
    rec # Allow the curent track to be recorded.
    start # Actually start the engne/transport rolling, so you can play.
    stop # Stop the engine, when you are finished recording your new track.
start:
  type: transport
  what: Start transport. Start the engine, to start recording or playing back.
  short: t
  parameters: none
  example: |
    doodle # Enter doodle mode.
    start # Start the engine/transport rolling, so you can play.
    stop # Stop the engine running.
getpos:
  type: transport
  what: Get the current playhead position (in seconds).
  short: gp
  parameters: none
  example: |
    start # Start the engine.
    gp # Get the current position of the playhead. "Where am I?"
setpos:
  type: transport
  what: Set current playhead position (in seconds).
  short: sp
  parameters: <f_position_seconds>
  example: setpos 65.0 # set current position to 65.0 seconds.
forward:
  type: transport
  what: Move playback position forwards (in seconds). Oldschool forwarding.
  short: fw
  parameters: <f_increment_seconds>
  example: fw 23.7 # forward 23.7 seconds from the current position.
rewind:
  type: transport
  what: Move playback position backwards (in seconds). Oldschool rewind.
  short: rw
  parameters: <f_decrement_seconds>
  example: rewind 6.5 # Move backwards 6.5 seconds from the current position.
to_start:
  type: transport
  what: Set the playback head to the start. A synonym for setpos 0.0 .
  short: beg
  parameters: none
to_end:
  type: transport
  what: Set the playback head to end minus 10 seconds.
  short: end
  parameters: none
ecasound_start:
  type: transport
  what: Ecasound-only start. Mainly useful for diagnostics and debugging. Use the command start in normal circumstances.
  short: T
  parameters: none
ecasound_stop:
  type: transport
  what: Ecasound-only stop. Mainly useful for diagnostics and debugging. Use command stop in normal circumstances.
  short: S
  parameters: none
restart_ecasound:
  type: transport
  what: Restart the Ecasound application again, when it has crashed or is behaving oddly.
  parameters: none
preview:
  type: transport
  what: Enter the preview mode. Configure Nama to allow playback and passthru of inputs (for mic test, rehearsals, etc.). Nothing is recorded to disk!
  parameters: none
  example: |
    rec # Set the current track to record from its input.
    preview # Enter the preview mode.
    start # You can hear the playback from previously recorded tracks and
          # play live. No file will be recorded to disk. You can adjust effects
          # and forward or rewind to suite your needs.
    stop # Stop the engine/transport.
    arm # Switch to normal recording/playback mode.
doodle:
  type: transport
  what: Enter the doodle mode. In doodle mode all live inputs from tracks - set to record - are enabled. Nama excludes multiple tracks having the same input. This mode is designed to allow rehearsing and adjusting effects without listening to playback -as in preview.
  parameters: none
  example: |
    doodle # Switch into doodle mode.
    start # start the engine/transport running.
    stop # Stop the engine.
    arm # Switch back to normal mode, where you get playback and record.
mixdown:
  type: mix
  what: Enter mixdown mode for subsequent engine runs. You will record new mixes, until you leave mixdown mode by mixoff.
  short: mxd
  parameters: none
  example: |
    mxd # Enter mixdown mode
    t # Start the engine running. A mix will be recorded into the Mixdown
      # track. Mixdown will stop automatically, when the longest track is at
      # its end.
    mxo # Return to the normal mode.
mixplay:
  type: mix
  what: Enter mixdown file playback mode, setting user tracks to OFF and only playing the Mixdown track. You can leave the mixplay mode by using mixoff.
  short: mxp
  parameters: none
  example: |
    mixplay # Enter the mixplay mode.
    start # Start playing back the Mixdown track only.
    stop # Stop playback.
    mxo # Switch back to normal mode.
mixoff:
  type: mix
  what: Leave the mixdown or mixplay mode. Set Mixdown track to OFF, user tracks to MON.
  short: mxo
  parameters: none
automix:
  type: mix
  what: Normalize track volume levels and fix DC-offsets. Then mix dwn to the Mixdown track.
  parameters: none
master_on:
  type: mix
  what: Turn on the mastering mode, adding tracks Eq, Low, Mid, High and Boost, if necessary. The mastering setup allows for one EQ and a three-band multiband compression and a final boosting stage. Leave the mastering mode by master_off.
  short: mr
  parameters: none
  example: |
    mr # Turn on master mode.
    start # Start the playback.
          # Now you can adjust the boost or global EQ.
    stop # Stop the engine.
master_off:
  type: mix
  what: Leave mastering mode. Remove the EQ, multi-band compression and Booster.
  short: mro
  parameters: none
add_track:
  type: track
  what: Create a new audio track.
  short: add new
  parameters: <s_name>
  example: |
    add_track clarinet # create a mono track called clarinet with input
                       # from soundcard channel 1.
add_tracks:
  type: track
  what: Create one or more new tracks in one go.
  parameters: <s_name1> [ <s_name2>... ]
  example: add_tracks violin viola contra_bass
link_track:
  type: track
  what: Create a read-only track, that uses audio files from another track.
  short: link
  parameters: <s_dest_name> <s_source_name> [ <s_project> ]
  example: |
    link part_1 Mixdown my_long_song_1 # Create a track called "part_1" linked
                                       # from the project my_long_song_1
    link_track piano_conp piano # Create a copy of the piano track (to apply
                                # extra compression to.)
import_audio:
  type: track
  what: Import a sound file (wav, ogg, mp3, etc.) to the current track, resampling it, if necessary.
  short: import
  parameters: <s_full_path_to_file> [ <i_frequency> ]
  example: |
    import /home/samples/bells.flac # import the file bells.flac into the
    import /home/music/song.mp3 44100 # Import song.mp3, where Nama can't find
           # the original samplerate (of 44.1kHz)
                                    # current track, making it the current
                                    # version of this track.
set_track:
  type: track
  what: Directly set current track parameters (use with care!).
  parameters: <s_track_field> <value>
record:
  type: track
  what: Set current track to record from its input (also known as REC-enabling).
  short: rec
  parameters: none
  example: |
    rec # Set current track to record.
    start # Whatever the other tracks are doing, this track will be recorded,
          # Meaning, that a new version will be recorded to disk.
    stop # Stop the recording/playback afterwards.
mon:
  type: track
  what: Set current track to playback the currently selected version. by default the last version is always played.
  short: on
  parameters: none
  example: mon # Next time you start, the last version will be played back.
off:
  type: track
  what: Set current track to OFF (exclude from setup). You can include the track with mon or rec.
  short: z
  parameters: none
rec_defeat:
  type: track
  what: Prevent writing an audio file for the current track. So the track will just pass thru the incoming audio. Useful for tracks connected to internal signal generators.
  short: rd
  parameters: none
rec_enable:
  type: track
  what: Allow writing an audio file for the current track. This is the opposite to rec_defeat. Useful to record a metronome or other special track to disk.
  short: re
  parameters: none
source:
  type: track
  what: Set the current track's input (source). This can be a soundcard channel or a JACK client name.
  short: src r
  parameters: <i_soundcard_channel> | 'null' | <s_jack_client_name> | <s_jack_port_name> | 'jack'
  example: |
    source 3 # Take input from soundcard channel number 3 (or 3 and 4, if stereo).
    source null # Track has no real input. this is useful for a metronome or
                # Ecasound's internal sine generator or some other sound
                # generator effect.
    src LinuxSampler # Record input from the JACK client named LinuxSampler.
    r synth:output_3 # record from the JACK client synth, only use the sound
                     # port output_3 (see he jackd and jack_lsp manpages
                     # for more information).
    src jack # Create connect to all ports listed in current_trackname.ports,
             # if it exists in the Nama project root directory. Ports are
             # listed pairwise in the .ports files for stereo tracks. This is
             # useful to record the mix of several mixrophones or minimalistic
             # outputs from other applications, such as hydrogen (one port per
             # sound of a drumkit).
send:
  type: track
  what: Set an aux send for the current track. Remove sends with remove_send .
  short: aux
  parameters: <i_soundcard_channel> | <s_jack_client_name> | <s_loop_id>
  example: |
    send 3 # Make an aux send to soundcard channel 3.
    send jconvolver # Make an aux send to the jconvolver JACK client.
remove_send:
  type: track
  what: Remove an aux send from the current track.
  short: nosend noaux
  parameters: none
stereo:
  type: track
  what: Set the current track to stereo (two channels). Will record two channels or easily import stereo audio files.
  parameters: none
mono:
  type: track
  what: Set the current track to mono (one channel). Will record one channel or easily import mono audio files (this is the default, when creating a track).
  parameters: none
set_version:
  type: track
  what: Set the active version of the current track for playback/monitoring (overrides group version setting).
  short: version ver
  parameters: <i_version_number>
  example: |
    piano # Select the piano track.
    version 2 # Switch the track to play back the second recorded of the
              # current track.
    sh # Display all information about the current track, also shows currently
       # selected version.
destroy_current_wav:
  type: track
  what: DESTRUCTIVE: Remove the current track's currently selected recording. This removes the underlying  audio file on your disk. USE WITH CARE!
  parameters: none
list_versions:
  type: track
  what: List versions of the current track. This will print the numbers of all versions of this track to the screen.
  short: lver
  parameters: none
  example: |
    list_versions # May print something like: 1 2 5 7 9
                  # The other versions might have been deleted earlier by you.
vol:
  type: track
  what: Change or show the current track's volume.
  short: v
  parameters: [ [ + | - | / | * ] <f_volume> ]
  example: |
    vol * 1.5 # Multiply the current volume by 1.5
    vol 75 # Set the current volume to 75 (depending on your setting in namarc
           # this means 75% of full volume (-ea) or 75 dB (-eadb).
    vol - 5.7 # Decrease current volume by 5.7 (percent or dB)
    vol # Display the current volume of the current track.
mute:
  type: track
  what: Mute the current track. Turn the current track's volume absolutely down. You can unmute the track with the command unmute.
  short: c cut
  parameters: none
unmute:
  type: track
  what: Restore previous volume level. It can be used after mute or solo.
  short: C uncut
  parameters: none
unity:
  type: track
  what: Set the current track's volume to unity. This will change the volume to the default value (100% or 0 dB).
  parameters: none
  example: |
    vol 55 # Set volume to 55
    unity # Set volume to the unity value.
    vol # Display the current volume (should be 100 or 0, depending on your
        # settings in namarc.
solo:
  type: track
  what: Mute all tracks but the current track or the tracks or bunches specified. You can reverse this with nosolo.
  short: sl
  parameters: [ <strack_name_1> | <s_bunch_name_1> ] [ <s_track_name_2 | <s_bunch_name_2> ] ...
  example: |
    solo # Will mute all tracks but the current track.
    nosolo # Will unmute all tracks again.
    solo piano bass Drums # Will mute everything but piano, bass and Drums.
nosolo:
  type: track
  what: Unjute all tracks, which have been turned down by solo. Tracks, that had beenmuted before the solo command stay muted.
  short: nsl
  parameters: none
all:
  type: track
  what: Unmute all tracks, this includes tracks muted by solo and other single tracks muted previously by mute.
  parameters: none
  example: |
    piano # Select track piano
    mute # Mute the piano track.
    sax # Selct the track sax.
    solo # mute all other tracks, except sax. Remember, that piano was muted
         # already
    all # unmute all tracks, including the piano track.
pan:
  type: track
  what: Change or display the current panning position of the current track. Panning is moving the audio in the stereo panorama between right and left. Position is given in percent. 0 is hard left and 100 hard right, 50% is dead centre.
  short: p
  parameters: [ <f_pan_position_in_percent> ]
  example: |
    pan 75 # Pan the track to a position between centre and hard right
    p 50 # Move the current track to the centre.
    pan # Show the current position of teh track in the stereo panorama.
pan_right:
  type: track
  what: Pan the current track hard right. this is a synonym for pan 100 . Can be reverse with pan_back .
  short: pr
  parameters: none
pan_left:
  type: track
  what: Pan the current track hard left. This is a synonym for pan 0 . Can be reversed with pan_back .
  short: pl
  parameters: none
pan_center:
  type: track
  what: Pan the current track to the centre. This is a synonym for pan 50 . Can be reversed with pan_back .
  short: pc
  parameters: none
pan_back:
  type: track
  what: Restore the current track's pan position prior to pan_left, pan_right or pan_center .
  short: pb
  parameters: none
show_tracks:
  type: track 
  what: Show a list of tracks, including their index number, volume, pan position, recording status and input.
  short: lt show
  parameters: none
show_tracks_all:
  type: track
  what: Show a list of all tracks, visible and hidden, with their ndex number, recording status, input, volume and pan position. This is mainly useful for diagnostics and debugging.
  short: sha showa
  parameters: none
show_bus_tracks:
  type: track 
  what: Show a list of tracks in the current bus.
  short: ltb showb
  parameters: none
show_track:
  type: track
  what: Display information about the current track, including index, recording status, effects, inserts, versions, stereo width (a.k.a. channel count) and controllers.
  short: sh
  parameters: none
show_mode:
  type: setup
  what: Display the current record/playback mode. this will indicate the mode - i.e. doodle, preview, etc. - and possible record/playback settings.
  short: shm
  parameters: none
show_track_latency:
  type: track
  what: display the latency information for the current track.
  short: shl
  parameters: none
show_latency_all:
  type: diagnostics
  what: Dump all latency data.
  short: shla
  parameters: none
set_region:
  type: track
  what: Specify a playback region for the current track using marks. Use the command new_region to create more than one region from a track. Can be reversed with remove_region .
  short: srg
  parameters: <s_start_mark_name> <s_end_mark_name>
  example: |
    sax # Switch to track sax, so it is the current track now.
    setpos 2.5 # Move the playhead to 2.5 seconds.
    mark sax_start # Create a mark there, caled sax_start
    sp 120.5 # Move playhead to 120.5 seconds.
    mark sax_end # Create a mark there, called sax_end
    set_region sax_start sax_end # Hide the track sax under a region called
                                 # sax, which contains the audio of original
                                 # track from 2.5 to 120.5 seconds.
add_region:
  type: track
  what: Create a region for the current track using an auxiliary track. This is a named region, which leaves the original track visible and untouched.
  short: arg
  parameters: <s_start_mark_name> | <f_start_time> <s_end_mark_name> | <f_end_time> [ <s_region_name> ]
  example: |
    sax # Select track sax as current track.
    new_region sax_start 66.7 trimmed_sax # Create the region trimmed sax.
               # This region contains the audio of track sax between the mark
               # sax_start and 66.7 seconds. You can use the region just like a
               # track, including commands remove-track and applying effects.
remove_region:
  type: track
  what: Remove the current region (including associated the auxiliary track).
  short: rrg
  parameters: none
shift_track:
  type: track
  what: Move the beginning of the track or region, also known as offsetting or shifting. Can be reversed by unshift_track .
  short: shift playat pat
  parameters: <s_start_mark_name> | <i_start_mark_index | <f_start_seconds>
  example: |
    piano # Select track piano as current track.
    shift 6.7 # Move the start of track to 6.7 seconds.
unshift_track:
  type: track
  what: Move the start of a track or region back to 0.0 seconds (the beginning of the setup.
  short: unshift
  parameters: none
modifiers:
  type: track
  what: Add/show modifiers for the current track (man ecasound for details). This is only useful in rare cases.
  short: mods mod
  parameters: [ Audio file sequencing parameters ]
  example: |
    modifiers select 5 15.2 # apply Ecasound's select modifier to the
                            # current track.
nomodifiers:
  type: track
  what: Remove modifiers from the current track.
  short: nomods nomod
  parameters: none
normalize:
  type: track
  what: Apply ecanormalize to the current track version. This will raise the gain/volume of the current track as far as possible and store it that way on disk. Note: this will permanently change the file.
  short: norm ecanormalize
  parameters: none
fixdc:
  type: track
  what: Fix the DC-offset of the current track using ecafixdc. Note: This will permanently change the file.
  short: ecafixdc
  parameters: none
autofix_tracks:
  type: track 
  what: apply the commands fixdc and normalize to all current version of all tracks, that are set to playback, i.e. MON .
  short: autofix
  parameters: none
remove_track:
  type: track
  what: Remove the current track. This will only remove the effects and display. all recorded audio will emain on your disk. The default is to ask, before Nama removes a track. this can be changed in namarc .
  parameters: none
bus_rec:
  type: bus
  what: Set a bus mix_track to record (the default behaviour).
  short: brec grec
  parameters: none
bus_mon:
  type: bus
  what: Set a bus mix_track to playback. This only does anything, if a complete bus has been cached/frozend/bounced before.
  short: bmon gmon
  parameters: none
bus_off:
  type: bus
  what: Set a bus mixtrack to OFF. Can be reversed with bus_rec and bus_mon.
  short: boff goff
  parameters: none
bus_version:
  type: group
  what: Set the default monitoring version for tracks in the current bus.
  short: bver gver
  parameters: none
add_bunch:
  type: group
  what: Define a bunch of tracks. A bunch is useful for shorter for statements.
  short: abn
  parameters: <s_bunch_name> [ <s_track_name_1> | <i_track_index_1> ] ...
  example: |
    new_bunch woodwind # Create an empty new bunch called woodwind.
    nb strings violin cello basso # Create the bunch strings with tracks
                                  # violin, cello and basso.
    for strings;mute # Mute all tracks in the strings bunch.
    for strings;vol * 0.8 # Lower the volume of all tracks in strings by a
                          # a factor of 0.8 (4/5).
list_bunches:
  type: group
  what: Dispaly a list of all bunches and their tracks.
  short: lbn
  parameters: none
remove_bunch:
  type: group
  what: Remove the specified bunches. This does not remove the tracks, only the groupings.
  short: rbn
  parameters: <s_bunch_name> [ <s_bunch_name> ] ...
add_to_bunch:
  type: group
  what: Add track(s) to a bunch.
  short: atbn
  parameters: <s_bunch_name> <s_track1> [ <s_track2> ] ...
  example: |
    add_to_bunch woodwind oboe sax_1 flute # Add oboe sax_1 and flute to the
                 # woodwind bunch or group of tracks.
commit:
  type: project
  what: commit Nama's current state
  short: ci
  parameters: <s_message>
tag:
  type: project
  what: git tag the current branch HEAD commit
  parameters: <s_tag_name> [<s_message>]
branch:
  type: project
  what: change to named branch
  short: br
  parameters: <s_branch_name>
list_branches:
  type: project
  what: list branches when called with no arguments
  short: lb lbr
  parameters: <s_branch_name>
new_branch:
  type: project
  what: create a new branch
  short: nbr
  parameters: <s_new_branch_name> [<s_existing_branch_name>]
save_state:
  type: project
  what: Save the project settings as file or tagged commit
  short: keep save
  parameters: [ <s_settings_target> [ <s_message> ] ]
get_state:
  type: project
  what: Retrieve project settings from file, branch or tag
  short: get recall retrieve
  parameters: <s_settings_target>
list_projects:
  type: project
  what: List all projects. This will list all Nama projects, which are stored in the Nama project root directory.
  short: lp
  parameters: none
new_project:
  type: project
  what: Create or open a new empty Nama project.
  short: create
  parameters: <s_new_project_name>
  example: create my_song # Will create empty project my_song.
    # Now you can start adding your tracks, editing them and mixing them.
load_project:
  type: project
  what: Load an existing project. This will load the project from the default project state file. If you wish to load a project state saved to a user specific file, load teh project and then use get_state.
  short: load
  parameters: <s_existing_project_name>
  example: load my_old_song # Will load my_old_song just as you left it.
project_name:
  type: project
  what: Display the name of the current project.
  short: project name
  parameters: none
new_project_template:
  type: project
  what: Make a project template based on the current project. This will include tracks and busses.
  short: npt
  parameters: <s_template_name> [ <s_template_description> ]
  example: |
    new_project_template my_band_setup "tracks and busses for bass, drums and me"
use_project_template:
  type: project
  what: Use a template to create tracks in a newly created, empty project.
  short: upt apt
  parameters: <s_template_name>
  example: |
    apt my_band_setup # Will add all the tracks for your basic band setup.
list_project_templates:
  type: project
  what: List all project templates.
  short: lpt
  parameters: none
destroy_project_template:
  type: project
  what: Remove one or more project templates.
  parameters: <s_template_name1> [ <s_template_name2> ] ...
generate:
  type: setup
  what: Generate an Ecasound chain setup for audio processing manually. Mainly useful for diagnostics and debugging.
  short: gen
  parameters: none
arm:
  type: setup
  what: Generate and connect a setup to record or playback. If you are in dodle or preview mode, this will bring you back to normal mode.
  parameters: none
arm_start:
  type: setup
  what: Generate and connect the setup and then start. This means, that you can directly record or listen to your tracks.
  short: arms
  parameters: none
connect:
  type: setup
  what: Connect the setup, so everything is ready to run. Ifusing JACK, this means, that Nama will connect to all the necessary JACK ports.
  short: con
  parameters: none
disconnect:
  type: setup
  what: Disconnect the setup. If running with JACK, this will disconnect from all JACK ports.
  short: dcon
  parameters: none
show_chain_setup:
  type: setup
  what: Show the underlying Ecasound chain setup for the current working condition. Mainly useful for diagnostics and debugging.
  short: chains
  parameters: none
loop:
  type: setup
  what: Loop the playback between two points. Can be stopped with loop_disable
  short: l
  parameters: <s_start_mark_name> | <i_start_mark_index> | <f_start_time_in_secs> <s_end_mark_name> | <i_end_mark_index> | <f_end_time_in_secs>
  example: |
    loop 1.5 10.0 # Loop between 1.5 and 10.0 seconds.
    loop 1 5 # Loop between marks with indeices 1 and 5, see list_marks.
    loop sax_start 12.6 # Loop between mark sax_start and 12.6 seconds.
noloop:
  type: setup
  what: Disable looping.
  short: nl
  parameters: none
add_controller:
  type: effect
  what: Add a controller to an effect (current effect, by default). Controllers can be modified by using mfx and remove using rfx.
  short: acl
  parameters: [ <s_operator_id> ] <s_effect_code> [ <f_param1> <f_param2> ] ...
  example: |
    add_effect etd 100 2 2 50 50 # Add a stero delay of 100ms.
    # the delay will get the effect ID E .
    # Now we want to slowly change the delay to 200ms.
    acl E klg 1 100 200 2 0 100 15 200 # Change the delay time linearly (klg)
        # from 100ms at the start (0 seconds) to 200ms at 15 seconds. See
        # help for -klg in the Ecasound manpage.
add_effect:
  type: effect
  what: Add an effect prefader (before vol/pan controls) to the current track. Remove effects with reove_effect.
  short: afx
  parameters: <s_effect_code> [ <f_param1> <f_param2>... ]
  example: |
    # We want to add the decimator effect (a LADSPA plugin).
    help_effect decimator # Print help about its paramters/controls.
                          # We see two input controls: bitrate and samplerate
    afx decimator 12 22050 # We have added the decimator with 12bits and a sample
                         # rate of 22050Hz.
  # NOTE the message printed to the screen, it can read like this:
  # Added GO (Decimator)
  # GO in this case is the unique effect ID, which yo will need to modify it.
append_effect:
  type: effect
  what: Add an effect postfader (after vol/pan conrols) to the current track. Remove effect with remove_effect.
  short: apfx
  parameters: <s_effect_code> [ <f_param1> <f_param2> ] ...
  example: |
    apfx var_dali # Append the Ecasound effect preset var_dali to the current
                  # track.
insert_effect:
  type: effect
  what: Place an effect before the specified unique effect ID. You will experience a short pause in playback.
  short: ifx
  parameters: <s_insert_point_id> <s_effect_code> [ <f_param1> <f_param2> ] ...
  example: |
    # Insert a delay before the reverb.
    lfx # List all effects. The reverb has unique effect ID AF .
    ifx AF etd 125 2 2 40 60 # Insert the etd delay before the reverb (AF).
modify_effect:
  type: effect
  what: Modify effect parameter(s).
  short: mfx modify_controller mcl
  parameters: [ <s_effect_id> ] <i_parameter> [ + | - | * | / ] <f_value>
  example: |
    # Modify the roomsize of our reverb.
    lfx # We see, that reverb has unique effect ID AF and roomsize is the
    # first parameter.
    mfx AF 1 62 # change the roomsize of reverb (AF) to 62.
    # We want to change roomsizes of both reverb AF and BG to 75.
    mfx AF,BG 1 75 # Change roomsize (parameter 1) of both AF and BG.
    mfx CE 6,10 -3 # Change parameters 6 and 10 of the effecit, with unique
                   # effect ID CE to -3 (good for adjusting dependent times
                   # in delays, volume levels in equalisers...)
    mfx D 4 + 10 # Increase the fourth parameter of effect D by 10.
    mfx A,B,C 3,6 * 5 # Adjust parameters 3 and 6 of effect A, B and C by a 
                      # factor of 5.
remove_effect:
  type: effect
  what: Remove effects. They don't have to be on the current track.
  short: rfx remove_controller rcl
  parameters: <s_effect_id1> [ <s_effect_id2> ] ...
position_effect:
  type: effect
  what: Position an effect before another effect (use 'ZZZ' for end).
  short: pfx
  parameters: <s_id_to_move> <s_position_id>
  example: |
    position_effect G F # Move effecit with unique ID G before F.
show_effect:
  type: effect
  what: Show information about an effect. Default is to print information on the current effect.
  short: sfx
  parameters: [ <s_effect_id1> ] [ <s_effect_id2> ] ...
  example: |
    sfx # Print name, unique ID and parameters/controls of the current effect.
    sfx H # Print out all information about effect with unique ID H.
list_effects:
  type: effect
  what: Print a short list of all effects on the current track, only including unique ID and effect name.
  short: lfx
  parameters: none
add_insert:
  type: effect 
  what: Add an external send/return insert to current track.
  short: ain
  parameters: ( pre | post ) <s_send_id> [ <s_return_id> ] -or- local (for wet/dry control)
  example: |
    add_insert pre jconvolver # Add a prefader insert (before vol/pan controls)
                              # the current track is sent to jconvolver and
                              # the return is picked up from jconvolver again.
    ain post jconvolver csound # Send the current track postfader (after vol/pan
                               # controls to jconvolver and get the return from
                               # csound. That would mean, that jconvolver and
                               # csound are somehow connected.
    guitar # Make guitar the current track.
    ain local # Create a local insert
    guitar-1-wet # Make the wet - or insert - track the current track.
    afx G2reverb 50 5.0 0.6 0.5 0 -16 -20 # add a reverb
    afx etc 6 100 45 2.5 # add a chorus effect on the reverbed signal
    guitar # Change back to the main guitar track
    wet 25 # Set the balance between wet/dry track to 25% wet, 75% dry.
set_insert_wetness:
  type: effect 
  what: Set wet/dry balance of the insert for the current track. The balance is given in percent, 0 meaning dry and 100 wet signal only.
  short: wet
  parameters: [ pre | post ] <n_wetness>
  example: |
    wet pre 50 # Set the prefader insert to be balanced 50/50 wet/dry.
    set_insert_wetness 100 # If there's only one insert on the current track,
                           # set it to full wetness.
remove_insert:
  type: effect
  what: Remove an insert from the current track.
  short: rin
  parameters: [ pre | post ]
  example: |
    rin # If there is only one insert on the current track, remove it.
    remove_insert post # Remove the postfader insert from the current track.
ctrl_register:
  type: effect
  what: List all Ecasound controllers. Controllers include linear controllers and oscillators.
  short: crg
  parameters: none
preset_register:
  type: effect
  what: List all Ecasound effect presets. See the Ecasound manpage for more detail on effect_presets.
  short: prg
  parameters: none
ladspa_register:
  type: effect
  what: List all LADSPA plugins, that Ecasound/Nama can find.
  short: lrg
  parameters: none
list_marks:
  type: mark
  what: List all marks with index, name and their respective positions in time.
  short: lmk lm
  parameters: none
to_mark:
  type: mark
  what: Move the playhead to the named mark or mark index.
  short: tmk tom
  parameters: <s_mark_name> | <i_mark_index>
  example: |
    to_mark sax_start # Jump to the position marked by sax_mark.
    tmk 2 # Move to the mark with the index 2.
add_mark:
  type: mark
  what: Drop a new mark at the current playback position. this will fail, if a mark is already placed on that exact position.
  short: mark amk
  parameters: [ <s_mark_id> ]
  example: |
    k important # Drop a mark named important at the current position.
remove_mark:
  type: mark
  what: Remove a mark. The default is to remove the current mark, if no parameter is given.
  short: rmk rom
  parameters: [ <s_mark_name> | <i_mark_index> ]
  example: |
    remove_mark important # remove the mark named important
    rmk 16 # Remove the mark with the index 16.
next_mark:
  type: mark
  what: Move the playhead to the next mark.
  short: nmk
  parameters: none
previous_mark:
  type: mark
  what: Move the playhead to the previous mark.
  short: pmk
  parameters: none
name_mark:
  type: mark
  what: Give a name to the current mark.
  parameters: <s_mark_name>
modify_mark:
  type: mark
  what: Change the position (time) of the current mark.
  short: move_mark mmk
  parameters: [ + | - ] <f_seconds>
  example: |
    move_mark + 2.3 # Move the current mark 2.3 seconds forward from its
                    # current position.
    mmk 16.8 # Move the current mark to 16.8 seconds, no matter, where it is now.
engine_status:
  type: diagnostics
  what: Display the Ecasound audio processing engine status.
  short: egs
  parameters: none
dump_track:
  type: diagnostics
  what: Dump current track data.
  short: dump
  parameters: none
dump_group:
  type: diagnostics 
  what: Dump group settings for user tracks.
  short: dumpg
  parameters: none
dump_all:
  type: diagnostics
  what: Dump most internal state data.
  short: dumpa
  parameters: none
dump_io:
  type: diagnostics
  what: Show chain inputs and outputs.
  parameters: none
list_history:
  type: help
  what: List the command history. Every project stores its own command history.
  short: lh
  parameters: none
add_send_bus_cooked:
  type: bus
  what: Add a send bus, that copies all user tracks with effects and inserts (a.k.a. cooked signals). All busses begin with a capital letter!
  short: asbc
  parameters: <s_name> <destination>
  example: |
    asbc Reverb jconv # Add a send bus called Reverb, that sends all output
                      # to the jconv JACK client.
add_send_bus_raw:
  type: bus
  what: Add a send bus, that copies all user tracks wihtout processing (a.k.a. raw signals). All busses begin with a capital letter!
  short: asbr
  parameters: <s_name> <destination>
  example: |
    asbr Reverb jconv # Add a raw send bus called Reverb, with its output
                      # going to the JACK client jconv .
add_sub_bus:
  type: bus
  what: Add a sub bus. This is a bus, as known from other DAWs. The default output goes to a mix track and that is routed to the mixer (the Master track). All busses begin with a capital letter!
  short: asub
  parameters: <s_name> [ <s_track_name> | <s_jack_client> | <i_soundcard_channel> ]
  example: |
    asub Brass # Add a sub bus Brass, which is routed to tne mixer.
    asub special csound # Add a sub bus, which is routed to the JACK client
                        # csound.
update_send_bus:
  type: bus
  what: Include tracks added since the send bus was created.
  short: usb
  parameters: <s_name>
  example: |
    update_send_bus Reverb # Include new tracks in the Reverb send bus.
remove_bus:
  type: bus
  what: Remove a bus.
  parameters: <s_bus_name>
list_buses:
  type: bus
  what: List buses and their parameters (TODO).
  short: lbs
  parameters: none
set_bus:
  type: bus
  what: Set bus parameters. This command is intended for advanced users.
  short: sbs
  parameters: <s_busname> <key> <value>
new_effect_chain:
  type: effect
  what: Create a new effect chain. An effect chain i a list of effects with all their parameters stored. Useful for creating small processing templates for frequently used instruments.
  short: nec
  parameters: <s_name> [ <effect_id_1>, <effect_id_2> ] ...
  example: |
    new_effect_chain my_piano # Create a new effect chain, called my_piano,
                              # storing all effects and their settings from
                              # the current track.
    nec my_guitar A C F G H # Create a new effect chain, calledmy_guitar,
                            # storing the effects with ID A, C, F, G and H and
                            # their respective settings.
add_effect_chain:
  type: effect
  what: Add an effect chain to the current track.
  short: aec
  parameters: <s_effect_chain_name>
  example: |
    aec my_piano # Add the effect chain, called my_piano, to the current track.
                 # This will add all effects stored in my_piano with their
                 # respective settings.
overwrite_effect_chain:
  type: effect
  what: Add an effect chain, overwriting or replacing the current effects. Current effects are pushed onto the bypass list, so they aren't lost completely.
  short: oec
  parameters: <s_effect_chain_name>
delete_effect_chain:
  type: effect
  what: Delete an effect chain definition. After that the effect chain will no longer be available to add. Projects, which use the effect chain won't be affected.
  short: dec destroy_effect_chain
  parameters: <s_effect_chain_name>
find_effect_chains:
  type: effect
  what: Dump effect chains, matching key/value pairs if provided
  short: fec
  parameters: [ <s_key_1> <s_value_1> ] ...
  example: |
    fec # List all effect chains with their effects.
find_user_effect_chains:
  type: effect
  what: List all *user* created effect chains, matching key/value pairs, if provided.
  short: fuec
  parameters: [ <s_key_1> <s_value_1> ] ...
bypass_effects:
  type: effect
  what: Bypass effects on the current track. With no parameters default to bypassing the current effect.
  short: bypass bfx
  parameters: [ <s_effect_id_1> <s_effect_id_2>... | 'all' ]
  example: |
    bypass all # Bypass all effects on the current track, except vol and pan.
    bypass AF # Only bypass the effecht with the unique ID AF.
bring_back_effects:
  type: effect
  what: Restore effects. If no parameter is given, the default is to restore the current effect.
  short: restore_effects bbfx
  parameters: [ <s_effect_id_1> <s_effect_id_2> ... | 'all' ]
  example: |
    bbfx # Restore the current effect.
    restore_effect AF # Restore the effect with the unique ID AF.
    bring_back_effects all # Restore all effects.
new_effect_profile:
  type: effect
  what: Create a new effect profile. An effect profile is a named group of effect chains for multiple tracks. Useful for storing a basic template of standard effects for a group of instruments, like a drum kit.
  short: nep
  parameters: <s_bunch_name> [ <s_effect_profile_name> ]
  example: |
    new_bunch Drums snare toms kick # Create a buch called Drums.
    nep Drums my_drum_effects # Create an effect profile, call my_drum_effects
                              # containing all effects from snare toms and kick.
apply_effect_profile:
  type: effect
  what: Apply an effect profile. this will add all the effects in it to the list of tracks stored in the effect profile. Note: You must give the tracks the same names as in the original project, where you created the effect profile.
  short: aep
  parameters: <s_effect_profile_name>
destroy_effect_profile:
  type: effect
  what: Delete an effect profile. This will delete the effect profile definition from your disk. All projects, which use this effect profile will NOT be affected.
  parameters: <s_effect_profile_name>
list_effect_profiles:
  type: effect
  what: List all effect profiles.
  short: lep
  parameters: none
show_effect_profiles:
  type: effect
  what: List effect profile.
  short: sepr
  parameters: none
full_effect_profiles:
  type: effect
  what: Dump effect profile data structure.
  short: fep
  parameters: none
cache_track:
  type: track
  what: Cache the current track, a.k.a. freezing or bouncing. Store a version of the current track with all processing to disk. Useful to save on processor power in large projects. Can be reversed by uncache_track .
  short: cache ct
  parameters: [ <f_additional_processing_time> ]
  example: |
      cache 10 # Cache the curent track and append 10 seconds extra time,
               # to allow a reverb or delay to fade away without being cut.
uncache_track:
  type: effect
  what: Select the uncached track version. This restores effects, but not inserts.
  short: uncache unc
  parameters: none
do_script:
  type: general
  what: Execute Nama commands from a file in the main project's directory or in the Nama project root directory. A script is a list of Nama commands, just as you would type them on the Nama prompt.
  short: do
  parameters: <s_filename>
  example: |
    do prepare_my_drums # Execute the script prepare_my_drums.
scan:
  type: general
  what: Re-read the project's .wav directory. Mainly useful for troubleshooting.
  parameters: none
add_fade:
  type: effect
  what: Add a fade-in or fade-out to the current track.
  short: afd fade
  parameters: ( in | out ) marks/times (see examples)
  example: |
    fade in mark1 # Fade in,starting at mark1 and using the default fade time
                  # of 0.5 seconds.
    fade out mark2 2 # Fade out over 2 seconds, starting at mark2 .
    fade out 2 mark2 # Fade out over 2 seconds, ending at mark2 .
    fade in mark1 mark2 # Fade in starting at mark1, ending at mark2 .
remove_fade:
  type: effect 
  what: Remove a fade from the current track.
  short: rfd
  parameters: <i_fade_index_1> [ <i_fade_index_2> ] ...
  example: |
    list_fade # Print a list of all fades and their tracks.
    rfd 2 # Remove the fade with the index (n) 2.
list_fade:
  type: effect
  what: List all fades.
  short: lfd
  parameters: none
add_comment:
  type: track
  what: Add a comment to the current track (replacing any previous comment). A comment maybe a short discription, notes on instrument settings, etc.
  short: comment ac
  parameters: <s_comment>
  example: ac "Guitar, treble on 50%"
remove_comment:
  type: track
  what: Remove a comment from the current track.
  short: rc
  parameters: none
show_comment:
  type: track
  what: Show the comment for the current track.
  short: sc
  parameters: none
show_comments:
  type: track
  what: Show all track comments.
  short: sca
  parameters: none
add_version_comment:
  type: track
  what: Add a version comment (replacing any previous user comment). This will add a comment for the current version of the current track.
  short: avc
  parameters: <s_comment>
  example: avc "The good take with the clear 6/8"
remove_version_comment:
  type: track
  what: Remove version comment(s) from the current track.
  short: rvc
  parameters: none
show_version_comment:
  type: track
  what: Show version comment(s) of the curent track.
  short: svc
  parameters: none
show_version_comments_all:
  type: track
  what: Show all version comments for the current track.
  short: svca
  parameters: none
set_system_version_comment:
  type: track
  what: Set a system version comment. Useful for testing and diagnostics.
  short: ssvc
  parameters: <s_comment>
midish_command:
  type: midi
  what: Send the command text to  the midish MIDI sequencer. Midish must be installed and enabled in namarc. See the midish manpage and fullonline documentation for more.
  short: m
  parameters: <s_command_text>
  example: m tracknew my_midi_track # create a new MIDI track in midish.
midish_mode_on:
  type: midi
  what: all users commands sent to midish, until
  short: mmo
midish_mode_off:
  what: exit midish mode, restore default Nama command mode, no midish sync
  type: midi
  short: mmx
midish_mode_off_ready_to_play:
  what: exit midish mode, sync midish start (p) with Ecasound
  type: midi
  short: mmxrp
midish_mode_off_ready_to_record:
  what: exit midish mode, sync midish start (r) with Ecasound
  type: midi
  short: mmxrr
new_edit:
  type: edit
  what: Create an edit for the current track and version.
  short: ned
  parameters: none
set_edit_points:
  type: edit
  what: Mark play-start, record-start and record-end positions for the current edit.
  short: sep
  parameters: none
list_edits:
  type: edit
  what: List all edits for current track and version.
  short: led
  parameters: none
select_edit:
  type: edit
  what: Select an edit to modify or delete. After selection it is the current edit.
  short: sed
  parameters: <i_edit_index>
end_edit_mode:
  type: edit
  what: Switch back to normal playback/record mode. The track will play full length again. Edits are managed via a sub- bus.
  short: eem
  parameters: none
destroy_edit:
  type: edit
  what: Remove an edit and all associated audio files. If no parameter is given, the default is to destroy the current edit. Note: The data will be lost permanently. Use with care!
  parameters: [ <i_edit_index> ]
preview_edit_in:
  type: edit
  what: Play the track region without the edit segment.
  short: pei
  parameters: none
preview_edit_out:
  type: edit
  what: Play the removed edit segment.
  short: peo
  parameters: none
play_edit:
  type: edit
  what: Play a completed edit.
  short: ped
  parameters: none
record_edit:
  type: edit
  what: Record an audio file for the current edit.
  short: red
  parameters: none
edit_track:
  type: edit
  what: set the edit track as the current track.
  short: et
  parameters: none
host_track_alias:
  type: edit
  what: Set the host track alias as the current track.
  short: hta
  parameters: none
host_track:
  type: edit
  what: Set the host track (edit sub-bus mix track) as the current track.
  short: ht
  parameters: none
version_mix_track:
  type: edit
  what: Set the version mix track as the current track.
  short: vmt
  parameters: none
play_start_mark:
  type: edit
  what: Select (and move to) play start mark of the current edit.
  short: psm
  parameters: none
rec_start_mark:
  type: edit
  what: Select (and move to) rec start mark of the current edit.
  short: rsm
  parameters: none
rec_end_mark:
  type: edit
  what: Select (and move to) rec end mark of the current edit.
  short: rem
  parameters: none
set_play_start_mark:
  type: edit
  what: Set play_start_mark to the current playback position.
  short: spsm
  parameters: none
set_rec_start_mark:
  type: edit
  what: Set rec_start_mark to the current playback position.
  short: srsm
  parameters: none
set_rec_end_mark:
  type: edit
  what: Set rec_end_mark to current playback position.
  short: srem
  parameters: none
disable_edits:
  type: edit
  what: Turn off the edits for the current track and playback the original. This will exclude the edit sub bus.
  short: ded
  parameters: none
merge_edits:
  type: edit
  what: Mix edits and original into a new host-track. this will write a new audio file to disk and the host track will have a new version for this.
  short: med
  parameters: none
explode_track:
  type: track
  what: Make the current track into a sub bus, with one track for each version.
  parameters: none
move_to_bus:
  type: track
  what: Move the current track to another bus. A new track is always in the Main bus. So to reverse this action use move_to_bus Main .
  short: mtb
  parameters: <s_bus_name>
  example: |
    asub Drums # Create a new sub bus, called Drums.
    snare # Make snare the current track.
    mtb Drums # Move the snare track into the sub bus Drums.
promote_version_to_track:
  type: track
  what: Create a read-only track using the specified version of the current track.
  short: pvt
  parameters: <i_version_number>
read_user_customizations:
  type: general
  what: Re-read the user customizations file 'custom.pl'.
  short: ruc
  parameters: none
limit_run_time:
  type: setup
  what: Stop recording after the last audio file finishes playing. Can be turned off with limit_run_time_off.
  short: lr
  parameters: [ <f_additional_seconds> ]
limit_run_time_off:
  type: setup
  what: Disable the recording stop timer.
  short: lro
  parameters: none
offset_run:
  type: setup
  what: Record/play from a mark, rather than from the start, i.e. 0.0 seconds.
  short: ofr
  parameters: <s_mark_name>
offset_run_off:
  type: setup
  what: Turn back to starting from 0.
  short: ofro
  parameters: none
view_waveform:
  type: general
  what: Launch mhwavedit to view/edit waveform of the current track and version. This requires to start Nama on a graphical terminal, like xterm or gterm or from GNOME via alt+F2 .
  short: wview
  parameters: none
edit_waveform:
  type: general
  what: Launch audacity to view/edit the waveform of the current track and version. This requires starting Nama on a graphical terminal like xterm or gterm or from GNOME starting Nama using alt+F2 .
  short: wedit
  parameters: none
rerecord:
  type: setup
  what: Record as before. This will set all the tracks to record, which have been recorded just before you listened back.
  short: rerec
  parameters: none
  example: |
    for piano guitar;rec # Set piano and guitar track to record.
    # do your recording and ilstening.
    # You want to record another version of both piano and guitar:
    rerec # Sets piano and guitar to record again.
eager:
  type: general
  what: Output audio as soon as possible. This will start playing or recording, as soon as a working setup is created.
  parameters: off | doodle | preview
  example: |
    eager doodle # Be eager in doodle mode.
    eager off # Turn off eagerness. Now you have to start yourself again.
analyze_level:
  type: track
  what: Print Ecasound amplitude analysis for current track. This will show highest volume and statistics.
  short: anl
  parameters: none
for:
  type: general
  what: Execute command(s) for several tracks.
  parameters: <s_track_name_1> [ <s_track_name_2>} ... ; <s_commands>
  example: |
    for piano guitar;vol / 2;pan 75 # For both piano and guitar adjust the
        # the volume by a factor of 1/2 and move the tracks to the right.
    for snare kick toms cymbals;mtb Drums # for each of these tracks do mtb Drums.
      # this will move all those tracks to the sub bus Drums in one command.
git:
  type: project
  what: execute git command in the project directory
  parameters: <s_command_name> [argument,...]
# config:
#   type: general
#   what: get or set project-specific config values (args may be quoted)
#   parameters: <s_parameter_name> [<s_arguments>]
# unset:
#   type: general
#   what: delete project-specific config values (fall back to global config)
#   parameters: <s_parameter_name>
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
	my $olddir = Audio::Nama::getcwd();
	my $prefix = "chdir ". Audio::Nama::project_dir().";";
	$shellcode = "$prefix $shellcode" if $shellcode =~ /^\s*git /;

	Audio::Nama::pager2( "executing this shell code:  $shellcode" )
		if $shellcode ne $item{shellcode};
	my $output = qx( $shellcode );
	chdir $olddir;
	Audio::Nama::pager2($output) if $output;
	1;
}



meta: eval perlcode stopper {
	Audio::Nama::logit(__LINE__,'Audio::Nama::Grammar','debug',"Evaluating perl code");
	Audio::Nama::eval_perl($item{perlcode});
	1
}


meta: for bunch_spec ';' namacode stopper { 
 	Audio::Nama::logit(__LINE__,'Grammar','debug',"namacode: $item{namacode}");
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
user_command: ident { $return = $item{ident} if $Audio::Nama::text->{user_command}->{$item{ident}} }






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
					
					
					
					
					 
					 
					 

save_target: /[-:\w.]+/
marktime: /\d+\.\d+/ 
markname: /[A-Za-z]\w*/ { 
	Audio::Nama::throw("$item[1]: non-existent mark name. Skipping"), return undef 
		unless $Audio::Nama::Mark::by_name{$item[1]};
	$item[1];
}

path: shellish
modifier: 'audioloop' | 'select' | 'reverse' | 'playat' | value
end: /[;\s]*$/ 		
					

help_effect: _help_effect effect { Audio::Nama::help_effect($item{effect}) ; 1}
find_effect: _find_effect anytag(s) { 
	Audio::Nama::find_effect(@{$item{"anytag(s)"}}); 1}
help: _help 'yml' { Audio::Nama::pager($Audio::Nama::text->{commands_yml}); 1}
help: _help anytag  { Audio::Nama::help($item{anytag}) ; 1}
help: _help { Audio::Nama::pager2( $Audio::Nama::help->{screen} ); 1}
project_name: _project_name { 
	Audio::Nama::pager2( "project name: ", $Audio::Nama::project->{name}); 1}
new_project: _new_project project_id { 
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
destroy_project_template: _destroy_project_template key(s) {
	Audio::Nama::remove_project_template(@{$item{'key(s)'}}); 1;
}

tag: _tag tagname message(?) {   
	Audio::Nama::save_state();
	Audio::Nama::git_snapshot();
	Audio::Nama::git_tag($item{tagname},@{$item{'message(?)'}});
	1;
}
commit: _commit message(?) { 
	Audio::Nama::save_state();
	Audio::Nama::git_snapshot(@{$item{'message(?)'}});
	1;
}
branch: _branch branchname { 
	Audio::Nama::throw("$item{branchname}: branch does not exist.  Skipping."), return 1
		if ! Audio::Nama::git_branch_exists($item{branchname});
	
	if(Audio::Nama::git_checkout($item{branchname})){
		Audio::Nama::load_project(name => $Audio::Nama::project->{name})
	} else { } 
	1;
}
branch: _branch { Audio::Nama::list_branches(); 1}

list_branches: _list_branches end { Audio::Nama::list_branches(); 1}

new_branch: _new_branch branchname branchfrom(?) { 
	my $name = $item{branchname};
	my $from = "@{$item{'branchfrom(?)'}}";
	Audio::Nama::throw("$name: branch already exists. Doing nothing."), return 1
		if Audio::Nama::git_branch_exists($name);
	Audio::Nama::git_create_branch($name, $from);
}
tagname: ident
branchname: ident
branchfrom: ident
message: /.+/

save_state: _save_state save_target message(?) { 
	my $name = $item{save_target};
	my $default_msg = "user save - $name";
	my $message = "@{$item{'message(?)'}}" || $default_msg;
	print "save target name: $name\n";
	print("commit message: $message\n") if $message;
	
	
	
	if(  ! $Audio::Nama::config->{use_git} or $name =~ /\.json$/ )
	{
	 	print("saving as file\n"), Audio::Nama::save_state( $name)
	}
	else 
	{
		

		Audio::Nama::save_state();
		if (Audio::Nama::state_changed() )
		{
			print("saving as a commit\n");
			Audio::Nama::git_commit($message);
			Audio::Nama::git_tag($name, $message); 
			Audio::Nama::pager3(qq[tagged HEAD commit as "$name"]);
		}
		else 
		{
			Audio::Nama::throw("nothing changed, so not committing or tagging")
		}
	}
	1
}
save_state: _save_state { Audio::Nama::save_state(); Audio::Nama::git_snapshot('user save'); 1}


get_state: _get_state save_target {
 	Audio::Nama::load_project( 
 		name => $Audio::Nama::project->{name},
 		settings => $item{save_target}
 		); 1}



getpos: _getpos {  
	Audio::Nama::pager2( Audio::Nama::d1( Audio::Nama::eval_iam q(getpos) )); 1}
setpos: _setpos timevalue {
	Audio::Nama::set_position($item{timevalue}); 1}
forward: _forward timevalue {
	Audio::Nama::forward( $item{timevalue} ); 1}
rewind: _rewind timevalue {
	Audio::Nama::rewind( $item{timevalue} ); 1}
timevalue: min_sec | seconds
seconds: samples  
seconds: /\d+/
samples: /\d+sa/ {
	my ($samples) = $item[1] =~ /(\d+)/;
 	
 	$return = $samples/$Audio::Nama::config->{sample_rate}
}
min_sec: /\d+/ ':' /\d+/ { $item[1] * 60 + $item[3] }

to_start: _to_start { Audio::Nama::to_start(); 1 }
to_end: _to_end { Audio::Nama::to_end(); 1 }
add_track: _add_track new_track_name {
	Audio::Nama::add_track($item{new_track_name});
    1
}
arg: anytag
add_tracks: _add_tracks track_name(s) {
	map{ Audio::Nama::add_track($_)  } @{$item{'track_name(s)'}}; 1}
new_track_name: anytag  { 
  	my $proposed = $item{anytag};
  	Audio::Nama::throw( qq(Track name "$proposed" needs to start with a letter)), 
  		return undef if  $proposed !~ /^[A-Za-z]/;
 	Audio::Nama::throw( qq(A track named "$proposed" already exists.)), 
 		return undef if $Audio::Nama::Track::by_name{$proposed};
 	Audio::Nama::throw( qq(Track name "$proposed" conflicts with Ecasound command keyword.)), 
 		return undef if $Audio::Nama::text->{iam}->{$proposed};
 
 	Audio::Nama::throw( qq(Track name "$proposed" conflicts with user command.)), 
 		return undef if $Audio::Nama::text->{user_command}->{$proposed};
 
  	Audio::Nama::throw( qq(Track name "$proposed" conflicts with Nama command or shortcut.)), 
  		return undef if $Audio::Nama::text->{commands}->{$proposed} 
				 or $Audio::Nama::text->{command_shortcuts}->{$proposed}; 
;
$proposed
} 
			
track_name: ident
existing_track_name: track_name { 
	my $track_name = $item{track_name};
	$return = $track_name, return if $Audio::Nama::tn{$track_name}; 
	print("$track_name: track does not exist.\n"),
	undef
}

move_to_bus: _move_to_bus existing_bus_name {
	$Audio::Nama::this_track->set( group => $item{existing_bus_name}); 1
} 
set_track: _set_track key someval {
	 $Audio::Nama::this_track->set( $item{key}, $item{someval} ); 1}
dump_track: _dump_track { Audio::Nama::pager($Audio::Nama::this_track->dump); 1}
dump_group: _dump_group { Audio::Nama::pager($Audio::Nama::bn{Main}->dump); 1}
dump_all: _dump_all { Audio::Nama::dump_all(); 1}
remove_track: _remove_track quiet end {
	Audio::Nama::remove_track_cmd($Audio::Nama::this_track, $item{quiet});
	1
}




remove_track: _remove_track end { 
		Audio::Nama::remove_track_cmd($Audio::Nama::this_track) ;
		1
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
add_region: _add_region beginning ending track_name(?) {
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
		Audio::Nama::pager2($Audio::Nama::this_track->name, qq(: Shifting start time to mark "$pos", $time seconds));
		$Audio::Nama::this_track->set(playat => $pos);
		1;
	} else { 
		Audio::Nama::throw( "Shift value is neither decimal nor mark name. Skipping.");
	0;
	}
}

start_position:  float | samples | mark_name
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
engine_status: _engine_status { Audio::Nama::pager2(Audio::Nama::eval_iam q(engine-status)); 1}
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

modifiers: _modifiers { Audio::Nama::pager2( $Audio::Nama::this_track->modifiers); 1}
nomodifiers: _nomodifiers { $Audio::Nama::this_track->set(modifiers => ""); 1}
show_chain_setup: _show_chain_setup { Audio::Nama::pager(Audio::Nama::ChainSetup::ecasound_chain_setup); 1}
dump_io: _dump_io { Audio::Nama::ChainSetup::show_io(); 1}
show_track: _show_track {
	my $output = $Audio::Nama::text->{format_top};
	$output .= Audio::Nama::show_tracks_section($Audio::Nama::this_track);
	$output .= Audio::Nama::show_region();
	$output .= Audio::Nama::show_versions();
	$output .= Audio::Nama::show_send();
	$output .= Audio::Nama::show_bus();
	$output .= Audio::Nama::show_modifiers();
	$output .= join "", "Signal width: ", Audio::Nama::width($Audio::Nama::this_track->width), "\n";
	$output .= Audio::Nama::show_inserts();
	$output .= Audio::Nama::show_effects();
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

show_mode: _show_mode { Audio::Nama::pager2( Audio::Nama::show_status()); 1}
bus_rec: _bus_rec {
	my $bus = $Audio::Nama::bn{$Audio::Nama::this_bus}; 
	$bus->set(rw => 'REC');
	
	$Audio::Nama::tn{$bus->send_id}->busify
		if $bus->send_type eq 'track' and $Audio::Nama::tn{$bus->send_id};
	Audio::Nama::pager2( "Setting REC-enable for " , $Audio::Nama::this_bus , " bus. You may record member tracks.");
	1; }
bus_mon: _bus_mon {
	my $bus = $Audio::Nama::bn{$Audio::Nama::this_bus}; 
	$bus->set(rw => 'MON');
	
	$Audio::Nama::tn{$bus->send_id}->busify
		if $bus->send_type eq 'track' and $Audio::Nama::tn{$bus->send_id};
	Audio::Nama::pager2( "Setting MON mode for " , $Audio::Nama::this_bus , " bus. Monitor only for member tracks.");
 	1  
}
bus_off: _bus_off {
	my $bus = $Audio::Nama::bn{$Audio::Nama::this_bus}; 
	$bus->set(rw => 'OFF');
	
	if($bus->send_type eq 'track' and my $mix = $Audio::Nama::tn{$bus->send_id})
	{ $mix->set(rw => 'OFF') }
	Audio::Nama::pager2( "Setting OFF mode for " , $Audio::Nama::this_bus, " bus. Member tracks disabled."); 1  
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
autofix_tracks: _autofix_tracks { Audio::Nama::process_command("for mon; fixdc; normalize"); 1 }
master_on: _master_on { Audio::Nama::master_on(); 1 }

master_off: _master_off { Audio::Nama::master_off(); 1 }

exit: _exit {   
	Audio::Nama::save_state(); 
	Audio::Nama::cleanup_exit();
	1
}	
source: _source source_id { $Audio::Nama::this_track->set_source($item{source_id}); 1 }
source_id: shellish
source: _source { 
	Audio::Nama::pager3($Audio::Nama::this_track->name, ": input set to ", $Audio::Nama::this_track->input_object_text, "\n",
	"however track status is ", $Audio::Nama::this_track->rec_status)
		if $Audio::Nama::this_track->rec_status ne 'REC';
	1;
}
send: _send send_id { $Audio::Nama::this_track->set_send($item{send_id}); 1}
send: _send { $Audio::Nama::this_track->set_send(); 1}
send_id: shellish
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
record: 'Xxx' {}
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
		Audio::Nama::throw(( $Audio::Nama::this_track->name . ": no volume control available")), return;
	Audio::Nama::modify_effect(
		$Audio::Nama::this_track->vol,
		1,
		undef,
		$item{value});
	1;
} 
vol: _vol sign(?) value { 
	$Audio::Nama::this_track->vol or 
		Audio::Nama::throw( $Audio::Nama::this_track->name . ": no volume control available"), return;
	Audio::Nama::modify_effect(
		$Audio::Nama::this_track->vol,
		1,
		$item{'sign(?)'}->[0],
		$item{value});
	1;
} 
vol: _vol { Audio::Nama::pager2( $Audio::Nama::fx->{params}->{$Audio::Nama::this_track->vol}[0]); 1}

mute: _mute { $Audio::Nama::this_track->mute; 1}

unmute: _unmute { $Audio::Nama::this_track->unmute; 1}


solo: _solo ident(s) {
	Audio::Nama::solo(@{$item{'ident(s)'}}); 1
}

solo: _solo { Audio::Nama::solo($Audio::Nama::this_track->name); 1}
all: _all { Audio::Nama::all() ; 1}
nosolo: _nosolo { Audio::Nama::nosolo() ; 1}

unity: _unity { Audio::Nama::unity($Audio::Nama::this_track); 1}

pan: _pan panval { 
	Audio::Nama::effect_update_copp_set( $Audio::Nama::this_track->pan, 0, $item{panval});
	1;} 
pan: _pan sign panval {
	Audio::Nama::modify_effect( $Audio::Nama::this_track->pan, 1, $item{sign}, $item{panval} );
	1;} 
panval: float 
      | dd
pan: _pan { Audio::Nama::pager2( $Audio::Nama::fx->{params}->{$Audio::Nama::this_track->pan}[0]); 1}
pan_right: _pan_right { Audio::Nama::pan_check($Audio::Nama::this_track, 100 ); 1}
pan_left:  _pan_left  { Audio::Nama::pan_check($Audio::Nama::this_track,    0 ); 1}
pan_center: _pan_center { Audio::Nama::pan_check($Audio::Nama::this_track,   50 ); 1}
pan_back:  _pan_back { Audio::Nama::pan_back($Audio::Nama::this_track); 1;}
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
add_mark: _add_mark ident { Audio::Nama::drop_mark $item{ident}; 1}
add_mark: _add_mark {  Audio::Nama::drop_mark(); 1}
next_mark: _next_mark { Audio::Nama::next_mark(); 1}
previous_mark: _previous_mark { Audio::Nama::previous_mark(); 1}
loop: _loop someval(s) {
	my @new_endpoints = @{ $item{"someval(s)"}}; 
	
	$Audio::Nama::mode->{loop_enable} = 1;
	@{$Audio::Nama::setup->{loop_endpoints}} = (@new_endpoints, @{$Audio::Nama::setup->{loop_endpoints}}); 
	@{$Audio::Nama::setup->{loop_endpoints}} = @{$Audio::Nama::setup->{loop_endpoints}}[0,1];
	1;}
noloop: _noloop { $Audio::Nama::mode->{loop_enable} = 0; 1}
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

		Audio::Nama::pager2("Added $id ($iname)");
		$Audio::Nama::this_op = $id;
	}
	else { Audio::Nama::pager2("Failed to add effect") } 
}


append_effect: _append_effect effect value(s?) {
	my $code = $item{effect};
	my $values = $item{"value(s?)"};
	Audio::Nama::throw(qq{$code: unknown effect. Try "find_effect keyword(s)}), return 1
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

		Audio::Nama::pager2( "Added $id ($iname)");
		$Audio::Nama::this_op = $id;
	}
 	1;
}

insert_effect: _insert_effect before effect value(s?) {
	my $before = $item{before};
	my $code = $item{effect};
	my $values = $item{"value(s?)"};
	
	Audio::Nama::pager2( join ", ", @{$values}) if $values;
	my $id = Audio::Nama::add_effect({
		before 	=> $before, 
		type	=> Audio::Nama::full_effect_code($code),
		values	=> $values,
	});
	if($id)
	{
		my $i = Audio::Nama::effect_index($code);
		my $iname = $Audio::Nama::fx_cache->{registry}->[$i]->{name};

		my $bi = 	Audio::Nama::effect_index(Audio::Nama::type($before));
		my $bname = $Audio::Nama::fx_cache->{registry}->[$bi]->{name};

 		Audio::Nama::pager2( "Inserted $id ($iname) before $before ($bname)");
		$Audio::Nama::this_op = $id;
	}
	1;}

before: op_id
parent: op_id
modify_effect: _modify_effect parameter(s /,/) value {
	Audio::Nama::throw("current effect is undefined, skipping"), return 1 if ! $Audio::Nama::this_op;
	Audio::Nama::modify_multiple_effects( 
		[$Audio::Nama::this_op], 
		$item{'parameter(s)'},
		undef,
		$item{value});
	Audio::Nama::pager2( Audio::Nama::show_effect($Audio::Nama::this_op))
}
modify_effect: _modify_effect parameter(s /,/) sign value {
	Audio::Nama::throw("current effect is undefined, skipping"), return 1 if ! $Audio::Nama::this_op;
	Audio::Nama::modify_multiple_effects( [$Audio::Nama::this_op], @item{qw(parameter(s) sign value)});
	Audio::Nama::pager2( Audio::Nama::show_effect($Audio::Nama::this_op));
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
	Audio::Nama::throw("current effect is undefined, skipping"), return 1 if ! $Audio::Nama::this_op;
	Audio::Nama::pager2( Audio::Nama::show_effect($Audio::Nama::this_op));
	1;
}
list_effects: _list_effects { Audio::Nama::pager(Audio::Nama::list_effects()); 1}
add_bunch: _add_bunch ident(s) { Audio::Nama::bunch( @{$item{'ident(s)'}}); 1}
list_bunches: _list_bunches { Audio::Nama::bunch(); 1}
remove_bunch: _remove_bunch ident(s) { 
 	map{ delete $Audio::Nama::project->{bunch}->{$_} } @{$item{'ident(s)'}}; 1}
add_to_bunch: _add_to_bunch ident(s) { Audio::Nama::add_to_bunch( @{$item{'ident(s)'}});1 }
list_versions: _list_versions { 
	Audio::Nama::pager2( join " ", @{$Audio::Nama::this_track->versions}); 1}
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
	Audio::Nama::pager2( grep{ ! $seen{$_}; $seen{$_}++ } @history );
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
	else { Audio::Nama::throw("$item{bus_name}: no such bus"); undef }
}

bus_name: ident 
user_bus_name: ident 
{
	if($item[1] =~ /^[A-Z]/){ $item[1] }
	else { Audio::Nama::throw("Bus name must begin with capital letter."); undef} 
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
	Audio::Nama::throw($Audio::Nama::this_track->name.  ": Missing or ambiguous insert. Skipping"), 
		return 1 unless $id;
	Audio::Nama::throw("wetness parameter must be an integer between 0 and 100"), 
		return 1 unless ($p <= 100 and $p >= 0);
	my $i = $Audio::Nama::Insert::by_index{$id};
	Audio::Nama::throw("track '",$Audio::Nama::this_track->n, "' has no insert.  Skipping."),
		return 1 unless $i;
	$i->set_wetness($p);
	1;
}
set_insert_wetness: _set_insert_wetness prepost(?) {
	my $prepost = $item{'prepost(?)'}->[0];
	my $id = Audio::Nama::Insert::get_id($Audio::Nama::this_track,$prepost);
	$id or Audio::Nama::throw($Audio::Nama::this_track->name.  ": Missing or ambiguous insert. Skipping"), return 1 ;
	my $i = $Audio::Nama::Insert::by_index{$id};
	 Audio::Nama::pager2( "The insert is ", $i->wetness, "% wet, ", (100 - $i->wetness), "% dry.");
}

remove_insert: _remove_insert prepost(?) { 

	
	
	
	my $prepost = $item{'prepost(?)'}->[0];
	my $id = Audio::Nama::Insert::get_id($Audio::Nama::this_track,$prepost);
	$id or Audio::Nama::throw($Audio::Nama::this_track->name.  ": Missing or ambiguous insert. Skipping"), return 1 ;
	Audio::Nama::pager2( $Audio::Nama::this_track->name.": removing $prepost". "fader insert");
	$Audio::Nama::Insert::by_index{$id}->remove;
	1;
}

cache_track: _cache_track additional_time(?) {
	my $time = $item{'additional_time(?)'}->[0];
	Audio::Nama::cache_track($Audio::Nama::this_track, $time); 1 
}
additional_time: float | dd
uncache_track: _uncache_track { Audio::Nama::uncache_track($Audio::Nama::this_track); 1 }
new_effect_chain: _new_effect_chain ident end {
	my $name = $item{ident};

	my ($old_entry) = Audio::Nama::EffectChain::find(user => 1, name => $name);

	
	
	my @options;
	push(@options, 'n' , $old_entry->n) if $old_entry;
	Audio::Nama::EffectChain->new(
		user   => 1,
		global => 1,
		name   => $item{ident},
		ops_list => [ $Audio::Nama::this_track->fancy_ops ],
		inserts_data => $Audio::Nama::this_track->inserts,
		@options,
	);
	1;
}
add_effect_chain: _add_effect_chain ident {
	my ($ec) = Audio::Nama::EffectChain::find(
		unique => 1, 
		user   => 1, 
		name   => $item{ident}
	);
	if( $ec ){ $ec->add($Audio::Nama::this_track) }
	else { Audio::Nama::throw("$item{ident}: effect chain not found") }
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
	push @args, @{ $item{'ident(s?)'} } if $item{'ident(s?)'};
	Audio::Nama::pager(map{$_->dump} Audio::Nama::EffectChain::find(@args));
}
find_user_effect_chains: _find_user_effect_chains ident(s?)
{
	my @args = ('user' , 1);
	push @args, @{ $item{'ident(s)'} } if $item{'ident(s)'};
	(scalar @args) % 2 == 0 
		or Audio::Nama::throw("odd number of arguments\n@args\n"), return 0;
	Audio::Nama::pager( map{ $_->summary} Audio::Nama::EffectChain::find(@args)  );
	1;
}




bypass_effects:   _bypass_effects op_id(s) { 
	my $arr_ref = $item{'op_id(s)'};
	return unless (ref $arr_ref) =~ /ARRAY/  and scalar @{$arr_ref};
	my @illegal = grep { ! Audio::Nama::fx($_) } @$arr_ref;
	Audio::Nama::throw("@illegal: non-existing effect(s), skipping."), return 0 if @illegal;
 	Audio::Nama::pager2( "track ",$Audio::Nama::this_track->name,", bypassing effects:");
	Audio::Nama::pager2( Audio::Nama::named_effects_list(@$arr_ref));
	Audio::Nama::bypass_effects($Audio::Nama::this_track,@$arr_ref);
	
	$Audio::Nama::this_op = $arr_ref->[0] if scalar @$arr_ref == 1;
}



bypass_effects: _bypass_effects 'all' { 
	Audio::Nama::pager2( "track ",$Audio::Nama::this_track->name,", bypassing all effects (except vol/pan)");
	Audio::Nama::bypass_effects($Audio::Nama::this_track, $Audio::Nama::this_track->fancy_ops)
		if $Audio::Nama::this_track->fancy_ops;
	1; 
}



bypass_effects: _bypass_effects { 
	Audio::Nama::throw("current effect is undefined, skipping"), return 1 if ! $Audio::Nama::this_op;
 	Audio::Nama::pager2( "track ",$Audio::Nama::this_track->name,", bypassing effects:"); 
	Audio::Nama::pager2( Audio::Nama::named_effects_list($Audio::Nama::this_op));
 	Audio::Nama::bypass_effects($Audio::Nama::this_track, $Audio::Nama::this_op);  
 	1; 
}
bring_back_effects:   _bring_back_effects end { 
	Audio::Nama::pager2("current effect is undefined, skipping"), return 1 if ! $Audio::Nama::this_op;
	Audio::Nama::pager2( "restoring effects:");
	Audio::Nama::pager2( Audio::Nama::named_effects_list($Audio::Nama::this_op));
	Audio::Nama::restore_effects( $Audio::Nama::this_track, $Audio::Nama::this_op);
}
bring_back_effects:   _bring_back_effects op_id(s) { 
	my $arr_ref = $item{'op_id(s)'};
	return unless (ref $arr_ref) =~ /ARRAY/  and scalar @{$arr_ref};
	my @illegal = grep { ! Audio::Nama::fx($_) } @$arr_ref;
	Audio::Nama::throw("@illegal: non-existing effect(s), aborting."), return 0 if @illegal;
	Audio::Nama::pager2( "restoring effects:");
	Audio::Nama::pager2( Audio::Nama::named_effects_list(@$arr_ref));
	Audio::Nama::restore_effects($Audio::Nama::this_track,@$arr_ref);
	
	$Audio::Nama::this_op = $arr_ref->[0] if scalar @$arr_ref == 1;
}
bring_back_effects:   _bring_back_effects 'all' { 
	Audio::Nama::pager2( "restoring all effects");
	Audio::Nama::restore_effects( $Audio::Nama::this_track, $Audio::Nama::this_track->fancy_ops);
}











effect_chain_id: effect_chain_id_pair(s) {
 		die " i found an effect chain id";
  		my @pairs = @{$item{'effect_chain_id_pair(s)'}};
  		my @found = Audio::Nama::EffectChain::find(@pairs);
  		@found and 
  			Audio::Nama::pager2(
				join " ", "found effect chain(s):",
  				map{ ('name:', $_->name, 'n', $_->n )} @found
			)
  			
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
	@alien and Audio::Nama::pager2("@alien: don't belong to track ",$Audio::Nama::this_track->name, "skipping."); 
	@belonging	
}

overwrite_effect_chain: _overwrite_effect_chain ident {
	Audio::Nama::overwrite_effect_chain($Audio::Nama::this_track, $item{ident}); 1;
}
bunch_name: ident { 
	Audio::Nama::is_bunch($item{ident}) or Audio::Nama::bunch_tracks($item{ident})
		or Audio::Nama::throw("$item{ident}: no such bunch name."), return; 
	$item{ident};
}

effect_profile_name: ident
existing_effect_profile_name: ident {
	Audio::Nama::pager2("$item{ident}: no such effect profile"), return
		unless Audio::Nama::EffectChain::find(profile => $item{ident});
	$item{ident}
}
new_effect_profile: _new_effect_profile bunch_name effect_profile_name {
	Audio::Nama::new_effect_profile($item{bunch_name}, $item{effect_profile_name}); 1 }
destroy_effect_profile: _destroy_effect_profile existing_effect_profile_name {
	Audio::Nama::delete_effect_profile($item{existing_effect_profile_name}); 1 }
apply_effect_profile: _apply_effect_profile existing_effect_profile_name {
	Audio::Nama::apply_effect_profile($item{effect_profile_name}); 1 }
list_effect_profiles: _list_effect_profiles {
	my %profiles;
	map{ $profiles{$_->profile}++ } Audio::Nama::EffectChain::find(profile => 1);
	my @output = keys %profiles;
	if( @output )
	{ Audio::Nama::pager( join " ","Effect Profiles available:", @output) }
	else { Audio::Nama::throw("no match") }
	1;
}
show_effect_profiles: _show_effect_profiles ident(?) {
	my $name;
	$name = $item{'ident(?)'}->[-1] if $item{'ident(?)'};
	$name ||= 1;
	my %profiles;
	map{ $profiles{$_->profile}++ } Audio::Nama::EffectChain::find(profile => $name);
	my @names = keys %profiles;


	my @output;


	for $name (@names) {
		push @output, "\nprofile name: $name\n";
		map { 	
			push @output, $_->summary;
		} Audio::Nama::EffectChain::find(profile => $name);
	} @names;
	if( @output )
	{ Audio::Nama::pager( @output); }
	else { Audio::Nama::throw("no match") }
	1;
}
full_effect_profiles: _full_effect_profiles ident(?) {
	my $name;
	$name = $item{'ident(?)'}->[-1] if $item{'ident(?)'};
	$name ||= 1;
	my @output = map{ $_->dump } Audio::Nama::EffectChain::find(profile => $name )  ;
	if( @output )
	{ Audio::Nama::pager( @output); }
	else { Audio::Nama::throw("no match") }
	1;
}
do_script: _do_script shellish { Audio::Nama::do_script($item{shellish});1}
scan: _scan { Audio::Nama::pager2( "scanning ", Audio::Nama::this_wav_dir()); Audio::Nama::restart_wav_memoize() }
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

list_fade: _list_fade {  Audio::Nama::pager(join "\n",
		map{ s/^---//; s/...\s$//; $_} map{$_->dump}
		sort{$a->n <=> $b->n} values %Audio::Nama::Fade::by_index) }
add_comment: _add_comment text { 
 	Audio::Nama::pager2( $Audio::Nama::this_track->name, ": comment: $item{text}"); 
 	$Audio::Nama::project->{track_comments}->{$Audio::Nama::this_track->name} = $item{text};
 	1;
}
remove_comment: _remove_comment {
 	Audio::Nama::pager2( $Audio::Nama::this_track->name, ": comment removed");
 	delete $Audio::Nama::project->{track_comments}->{$Audio::Nama::this_track->name};
 	1;
}
show_comment: _show_comment {
	map{ Audio::Nama::pager2( "(",$_->group,") ", $_->name, ": ", $_->comment) } $Audio::Nama::this_track;
	1;
}
show_comments: _show_comments {
	map{ Audio::Nama::pager2( "(",$_->group,") ", $_->name, ": ", $_->comment) } Audio::Nama::Track::all();
	1;
}
add_version_comment: _add_version_comment dd(?) text {
	my $t = $Audio::Nama::this_track;
	my $v = $item{'dd(?)'}->[0] // $t->monitor_version // return 1;
	Audio::Nama::pager2( $t->add_version_comment($v,$item{text})); 
}	
remove_version_comment: _remove_version_comment dd {
	my $t = $Audio::Nama::this_track;
	Audio::Nama::pager2( $t->remove_version_comment($item{dd})); 1
}
show_version_comment: _show_version_comment dd(s?) {
	my $t = $Audio::Nama::this_track;
	my @v = @{$item{'dd(s?)'}};
	if(!@v){ @v = $t->monitor_version}
	@v or return 1;
	$t->show_version_comments(@v);
	 1;
}
show_version_comments_all: _show_version_comments_all {
	my $t = $Audio::Nama::this_track;
	my @v = @{$t->versions};
	$t->show_version_comments(@v); 1;
}
set_system_version_comment: _set_system_version_comment dd text {
	Audio::Nama::pager2( Audio::Nama::set_system_version_comment($Audio::Nama::this_track,@item{qw(dd text)}));1;
}
midish_command: _midish_command text {
	Audio::Nama::midish_command( $item{text} ); 1
}
midish_mode_on: _midish_mode_on { 
	Audio::Nama::pager("Setting midish terminal mode!! Return with 'midish_mode_off'.");
	$Audio::Nama::mode->{midish_terminal}++;
}
 
midish_mode_off: _midish_mode_off { 
	Audio::Nama::pager("Releasing midish terminal mode. Sync is not enabled.");
	undef $Audio::Nama::mode->{midish_terminal};
	undef $Audio::Nama::mode->{midish_transport_sync};
	1;
}
midish_mode_off_ready_to_play: _midish_mode_off_ready_to_play { 
	Audio::Nama::pager("Releasing midish terminal mode.
Will sync playback with Ecasound."); 
	undef $Audio::Nama::mode->{midish_terminal} ;
	$Audio::Nama::mode->{midish_transport_sync} = 'play';
	1;
}
midish_mode_off_ready_to_record: _midish_mode_off_ready_to_record { 
	Audio::Nama::pager("Releasing midish terminal mode. 
Will sync record with Ecasound.");
	undef $Audio::Nama::mode->{midish_terminal} ;
	$Audio::Nama::mode->{midish_transport_sync} = 'record';
	1;
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
	$t->versions->[$v] or Audio::Nama::pager2($t->name,": version $v does not exist."),
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
	my $sign = $item{'sign(?)'}->[-1]; 
	$Audio::Nama::setup->{runtime_limit} = $sign
		? eval "$Audio::Nama::setup->{audio_length} $sign $item{dd}"
		: $item{dd};
	Audio::Nama::pager2( "Run time limit: ", Audio::Nama::heuristic_time($Audio::Nama::setup->{runtime_limit})); 1;
}
limit_run_time_off: _limit_run_time_off { 
	Audio::Nama::pager2( "Run timer disabled");
	Audio::Nama::disable_length_timer();
	1;
}
offset_run: _offset_run markname {
	Audio::Nama::offset_run( $item{markname} ); 1
}
offset_run_off: _offset_run_off {
	Audio::Nama::pager2( "no run offset.");
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
	else { Audio::Nama::throw("Mhwaveedit not found. No waveform viewer is available.") }
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
	else { Audio::Nama::throw("Audacity not found. No waveform editor available.") }
	1;
}

rerecord: _rerecord { 
		Audio::Nama::pager2(
			scalar @{$Audio::Nama::setup->{_last_rec_tracks}} 
				?  "Toggling previous recording tracks to REC"
				:  "No tracks in REC list. Skipping."
		);
		
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
	Audio::Nama::pager2( Audio::Nama::yaml_out($node)) if $node;
	1;
}
show_latency_all: _show_latency_all { 
	Audio::Nama::pager2( Audio::Nama::yaml_out($Audio::Nama::setup->{latency})) if $Audio::Nama::setup->{latency};
	1;
}
analyze_level: _analyze_level { Audio::Nama::check_level($Audio::Nama::this_track);1 }
git: _git shellcode stopper { 

Audio::Nama::pager2(map {$_.="\n"} $Audio::Nama::project->{repo}->run( split " ", $item{shellcode})) 
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
command: record
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
command: add_region
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
command: add_bunch
command: list_bunches
command: remove_bunch
command: add_to_bunch
command: commit
command: tag
command: branch
command: list_branches
command: new_branch
command: save_state
command: get_state
command: list_projects
command: new_project
command: load_project
command: project_name
command: new_project_template
command: use_project_template
command: list_project_templates
command: destroy_project_template
command: generate
command: arm
command: arm_start
command: connect
command: disconnect
command: show_chain_setup
command: loop
command: noloop
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
command: add_mark
command: remove_mark
command: next_mark
command: previous_mark
command: name_mark
command: modify_mark
command: engine_status
command: dump_track
command: dump_group
command: dump_all
command: dump_io
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
command: destroy_effect_profile
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
command: midish_mode_on
command: midish_mode_off
command: midish_mode_off_ready_to_play
command: midish_mode_off_ready_to_record
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
command: analyze_level
command: for
command: git
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
_add_tracks: /add_tracks\b/
_link_track: /link_track\b/ | /link\b/
_import_audio: /import_audio\b/ | /import\b/
_set_track: /set_track\b/
_record: /record\b/ | /rec\b/
_mon: /mon\b/ | /on\b/
_off: /off\b/ | /z\b/
_rec_defeat: /rec_defeat\b/ | /rd\b/
_rec_enable: /rec_enable\b/ | /re\b/
_source: /source\b/ | /src\b/ | /r\b/
_send: /send\b/ | /aux\b/
_remove_send: /remove_send\b/ | /nosend\b/ | /noaux\b/
_stereo: /stereo\b/
_mono: /mono\b/
_set_version: /set_version\b/ | /version\b/ | /ver\b/
_destroy_current_wav: /destroy_current_wav\b/
_list_versions: /list_versions\b/ | /lver\b/
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
_show_bus_tracks: /show_bus_tracks\b/ | /ltb\b/ | /showb\b/
_show_track: /show_track\b/ | /sh\b/
_show_mode: /show_mode\b/ | /shm\b/
_show_track_latency: /show_track_latency\b/ | /shl\b/
_show_latency_all: /show_latency_all\b/ | /shla\b/
_set_region: /set_region\b/ | /srg\b/
_add_region: /add_region\b/ | /arg\b/
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
_bus_version: /bus_version\b/ | /bver\b/ | /gver\b/
_add_bunch: /add_bunch\b/ | /abn\b/
_list_bunches: /list_bunches\b/ | /lbn\b/
_remove_bunch: /remove_bunch\b/ | /rbn\b/
_add_to_bunch: /add_to_bunch\b/ | /atbn\b/
_commit: /commit\b/ | /ci\b/
_tag: /tag\b/
_branch: /branch\b/ | /br\b/
_list_branches: /list_branches\b/ | /lb\b/ | /lbr\b/
_new_branch: /new_branch\b/ | /nbr\b/
_save_state: /save_state\b/ | /keep\b/ | /save\b/
_get_state: /get_state\b/ | /get\b/ | /recall\b/ | /retrieve\b/
_list_projects: /list_projects\b/ | /lp\b/
_new_project: /new_project\b/ | /create\b/
_load_project: /load_project\b/ | /load\b/
_project_name: /project_name\b/ | /project\b/ | /name\b/
_new_project_template: /new_project_template\b/ | /npt\b/
_use_project_template: /use_project_template\b/ | /upt\b/ | /apt\b/
_list_project_templates: /list_project_templates\b/ | /lpt\b/
_destroy_project_template: /destroy_project_template\b/
_generate: /generate\b/ | /gen\b/
_arm: /arm\b/
_arm_start: /arm_start\b/ | /arms\b/
_connect: /connect\b/ | /con\b/
_disconnect: /disconnect\b/ | /dcon\b/
_show_chain_setup: /show_chain_setup\b/ | /chains\b/
_loop: /loop\b/ | /l\b/
_noloop: /noloop\b/ | /nl\b/
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
_add_mark: /add_mark\b/ | /mark\b/ | /amk\b/
_remove_mark: /remove_mark\b/ | /rmk\b/ | /rom\b/
_next_mark: /next_mark\b/ | /nmk\b/
_previous_mark: /previous_mark\b/ | /pmk\b/
_name_mark: /name_mark\b/
_modify_mark: /modify_mark\b/ | /move_mark\b/ | /mmk\b/
_engine_status: /engine_status\b/ | /egs\b/
_dump_track: /dump_track\b/ | /dump\b/
_dump_group: /dump_group\b/ | /dumpg\b/
_dump_all: /dump_all\b/ | /dumpa\b/
_dump_io: /dump_io\b/
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
_delete_effect_chain: /delete_effect_chain\b/ | /dec\b/ | /destroy_effect_chain\b/
_find_effect_chains: /find_effect_chains\b/ | /fec\b/
_find_user_effect_chains: /find_user_effect_chains\b/ | /fuec\b/
_bypass_effects: /bypass_effects\b/ | /bypass\b/ | /bfx\b/
_bring_back_effects: /bring_back_effects\b/ | /restore_effects\b/ | /bbfx\b/
_new_effect_profile: /new_effect_profile\b/ | /nep\b/
_apply_effect_profile: /apply_effect_profile\b/ | /aep\b/
_destroy_effect_profile: /destroy_effect_profile\b/
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
_show_comments: /show_comments\b/ | /sca\b/
_add_version_comment: /add_version_comment\b/ | /avc\b/
_remove_version_comment: /remove_version_comment\b/ | /rvc\b/
_show_version_comment: /show_version_comment\b/ | /svc\b/
_show_version_comments_all: /show_version_comments_all\b/ | /svca\b/
_set_system_version_comment: /set_system_version_comment\b/ | /ssvc\b/
_midish_command: /midish_command\b/ | /m\b/
_midish_mode_on: /midish_mode_on\b/ | /mmo\b/
_midish_mode_off: /midish_mode_off\b/ | /mmx\b/
_midish_mode_off_ready_to_play: /midish_mode_off_ready_to_play\b/ | /mmxrp\b/
_midish_mode_off_ready_to_record: /midish_mode_off_ready_to_record\b/ | /mmxrr\b/
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
_limit_run_time: /limit_run_time\b/ | /lr\b/
_limit_run_time_off: /limit_run_time_off\b/ | /lro\b/
_offset_run: /offset_run\b/ | /ofr\b/
_offset_run_off: /offset_run_off\b/ | /ofro\b/
_view_waveform: /view_waveform\b/ | /wview\b/
_edit_waveform: /edit_waveform\b/ | /wedit\b/
_rerecord: /rerecord\b/ | /rerec\b/
_eager: /eager\b/
_analyze_level: /analyze_level\b/ | /anl\b/
_for: /for\b/
_git: /git\b/
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

# audio file format templates

mix_to_disk_format: s16_le,N,frequency,i
raw_to_disk_format: s16_le,N,frequency,i
cache_to_disk_format: f24_le,N,frequency,i

mixdown_encodings: mp3 ogg

sample_rate: frequency

# globals for our chain setups

ecasound_globals_general: -z:mixmode,sum -G:jack,Nama,send
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

#### State management ####

# use_git: 1
# autosave: 0

#### Julien Claassen's Notes on Mastering effect defaults
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
# ~/nama/untitled/State.json    # version controlled project state
# ~/nama/untitled/Aux.json      # additional project state
# ~/nama/untitled/Setup.ecs		# Ecasound chain setup
# ~/nama/.effects_cache			# static effects data
# ~/nama/global_effect_chains.json # User defined effect chains and profiles

# end

@@ custom_pl
### custom.pl - Nama user customization file

# See notes at end

##  Prompt section - replaces default user prompt

prompt =>  
	q{
	git_branch_display(). "nama [". ($this_bus eq 'Main' ? '': "$this_bus/").  
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