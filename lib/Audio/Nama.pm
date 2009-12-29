## Note on object model
# 
# All graphic method are defined in the base class :: .
# These are overridden in the Audio::Nama::Text class with no-op stubs.
# 
# So all the routines in Graphical_methods.pl can consider
# themselves to be in the base class.

# How is $ui->init_gui interpreted? If $ui is class Audio::Nama::Text
# Nama finds a no-op init_gui stub in package Audio::Nama::Text.
#
# If $ui is class Audio::Nama::Graphical, 
# Nama looks for init_gui() in package Audio::Nama::Graphical,
# finds nothing, so goes to look in the root namespace ::
# of which Audio::Nama::Text and Audio::Nama::Graphical are both descendants.

package Audio::Nama;
require 5.10.0;
use vars qw($VERSION);
$VERSION = '1.00';
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
	@status_vars,    # we will dump them for diagnostic use
	%abbreviations, # for replacements in config files

	$ecasound_globals_realtime,     # .namarc field
	$ecasound_globals_default,  # .namarc field
	$ecasound_tcp_port,  # for Ecasound NetECI interface
	$saved_version, # copy of $VERSION saved with settings in State.yml


	$default,		# the internal default configuration file, as string
	$default_palette_yml, # not horriffic is about all I can say
					
	$raw_to_disk_format,
	$mix_to_disk_format,
	$mixer_out_format,
	$execute_on_project_load, # Nama text commands 
	$use_group_numbering, # same version number for tracks recorded together

	# .namarc mastering fields
    $mastering_effects, # apply on entering mastering mode
	$eq, 
	$low_pass,
	$mid_pass,
	$high_pass,
	$compressor,
	$spatialiser,
	$limiter,

	$initial_user_mode, # preview, doodle, 0, undef TODO
	
	$yw,			# yaml writer object
	$yr,			# yaml reader object
	%state_c_ops, 	# intermediate copy for storage/retrieval
	$effects_cache_file, # where we keep info on Ecasound
					# and LADSPA effects, presets, etc.
	
	$ecasound, 		# the name to invoke when we want to kill ecasound

	$grammar, 		# filled by Grammar.pm
	$parser,		# for the objected created by Parse::RecDescent
	%iam_cmd,		# for identifying IAM commands in user input
	@nama_commands,# array of commands my functions provide
	%nama_commands,# as hash as well
	$project_root,	# each project will get a directory here
	                # and one .nama directory, also with 
	
					#
					# $ENV{HOME}/.namarc
					# $ENV{HOME}/nama/paul_brocante
					# $ENV{HOME}/nama/paul_brocante/.wav/vocal_1.wav
					# $ENV{HOME}/nama/paul_brocante/Store.yml
					# $ENV{HOME}/nama/.effects_cache
					# $ENV{HOME}/nama/paul_brocante/.namarc 

					 #this_wav_dir = 
	$state_store_file,	# filename for storing @persistent_vars
	$effect_chain_file, # for storing effect chains
	$chain_setup_file, # Ecasound uses this 

	$tk_input_channels,# this many radiobuttons appear
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
	$old_this_track, # when we need to save/restore current track
	$this_op,      # currently selected effect # future
	$this_mark,    # current mark  # for future

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
	$sn_dump,  # button to dump status

	# new object core
	
	$main_bus, 
	$main, # main_group
	$null_bus,
    $null, # group

	%ti, # track by index (alias %Audio::Nama::Track::by_index)
	%tn, # track by name  (alias %Audio::Nama::Track::by_name)

	@tracks_data, # staging for saving
	@bus_data,   # 
	@groups_data, # 
	@marks_data, # 

	$alsa_playback_device,
	$alsa_capture_device,

	$main_out, # do I route audio output to soundcard?

	# rules
	
	$mon_setup,
	$rec_file,
	$rec_setup,
	$aux_send,
	$null_setup,

	$send_bus_out,
	
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
	$sock, 			# socket for Net-ECI mode
	%versions,		# store active versions for use after engine run
	@io, 			# accumulate IO objects for generating setup
	$track_snapshots, # to save recalculating for each IO object
	$chain_setup,	# current chain setup
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
						$mixer_out_format
						$alsa_playback_device
						$alsa_capture_device	
						$project_root 	
						$use_group_numbering
						$press_space_to_start_transport
						$execute_on_project_load
						$initial_user_mode
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
						$loop_enable
						@loop_endpoints
						$length
						%bunch
						$mastering_mode
						@command_history
						$saved_version
						$main_out
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
$chain_setup_file = 'Setup.ecs'; # For loading by Ecasound
$tk_input_channels = 10;
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

jack_update(); # to be polled by Event
$memoize = 1;

@mastering_track_names = qw(Eq Low Mid High Boost);

init_memoize() if $memoize;

# aliases for concise access

*tn = \%Audio::Nama::Track::by_name;
*ti = \%Audio::Nama::Track::by_index;

# $ti{3}->rw

# print remove_spaces("bulwinkle is a...");


## Class and Object definitions for package 'Audio::Nama'

our @ISA; # no anscestors
use Audio::Nama::Object qw(mode);

## The following methods belong to the root class

sub hello {"superclass hello"}

sub new { my $class = shift; return bless {@_}, $class }

sub main { 
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
	poll_jack();
	initialize_terminal();

	if (! $project_name ){
		$project_name = "untitled";
		$opts{c}++; 
	}
	print "\nproject_name: $project_name\n";
	
	if ($project_name){
		load_project( name => $project_name, create => $opts{c}) ;
	}
	1;	
}
sub issue_first_prompt {
	$term->stuff_char(10); # necessary to respond to Ctrl-C at first prompt 
	&{$attribs->{'callback_read_char'}}();
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
	#$event_id{sigint} = AE::signal('INT', \&cleanup_exit);

}
sub revise_prompt {
    $term->callback_handler_install(prompt(), \&process_line);
}
sub prompt {
	"nama". ($this_track ? " [".$this_track->name."]" : '') . " ('h' for help)> "
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

	my @c = `which file`;
	@c or print ( <<WARN
BSD utility program 'file' not found
in $ENV{PATH}, your shell's list of executable 
directories. This program is currently required
to be able to play back mixes in stereo.
WARN
	) and sleeper (0.6);
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
		can_load( modules =>{ Event => undef});
		import Event qw(loop unloop unloop_all);
	}
	can_load( modules => {AnyEvent => undef});

}
	
{
my $default_port = 2868; # Ecasound's default
sub launch_ecasound_server {
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
sub colonize { # convert seconds to hours:minutes:seconds 
	my $sec = shift;
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
sub project_root { $proot{$project_root} ||= File::Spec::Link->resolve_all($project_root)};
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
sub project_dir  {$project_name and join_path( project_root(), $project_name)
}

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
			rw => 'MON',); # no dir, we won't record tracks


		 Audio::Nama::Track->new( 
			group => 'Mixdown', 
			name => 'Mixdown', 
			width => 2,
			rw => 'MON'); 
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
	$null_bus = Audio::Nama::Bus->new(name => 'Null');
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
	Audio::Nama::Group->initialize();
	create_groups();
	Audio::Nama::Track->initialize();

	%inputs = %outputs = ();

}
sub create_groups {

	Audio::Nama::Group->new(name => 'Master'); # master fader
	Audio::Nama::Group->new(name => 'Mixdown', rw => 'REC');
	Audio::Nama::Group->new(name => 'Mastering'); # mastering network
	Audio::Nama::Group->new(name => 'Insert'); # auxiliary tracks for inserts
	Audio::Nama::Group->new(name => 'Cooked'); # used by CacheRec tracks
	Audio::Nama::Group->new(name => 'Temp'); # tracks to be removed
								#	after generating chain setup
	$main = Audio::Nama::Group->new(name => 'Main', rw => 'REC');
	$null    = Audio::Nama::Group->new(name => 'null');
}

## track and wav file handling

# create read-only track pointing at WAV files of specified
# track name in a different project

sub add_track_alias_project {
	my ($name, $track, $project) = @_;
	my $dir =  join_path(project_root(), $project, '.wav'); 
	if ( -d $dir ){
		if ( glob "$dir/$track\_*.wav"){
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

	my $group = $Audio::Nama::Group::by_name{$track->group}; 
	command_process('for mon; mon') if $preview and $group->rw eq 'MON';
	$group->set(rw => 'REC') unless $track->target; # not if is alias

	# normal tracks default to 'REC'
	# track aliases default to 'MON'
	$track->set(rw => $track->target
					?  'MON'
					:  'REC') ;
	$track_name = $ch_m = $ch_r = undef;

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
		 unless $Audio::Nama::Group::by_name{$h{group}};
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
				type => 'ea',
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
	map{ /-o:(.*?\.wav)$/} grep{ /-o:/ and /\.wav$/} split "\n", $chain_setup
}

sub generate_setup { # catch errors and cleanup
					 
	local $@;
	eval { &generate_setup_try };
	return 1 unless $@;
	say("error caught while generating setup: $@");
	remove_temporary_tracks();
	track_unmemoize();
	0;
}
sub generate_setup_try { 

	$debug2 and print "&generate_setup\n";
	track_memoize(); # assume track state frozen during generate setup

	my $automix = shift; # route Master to null_out if present

	# save current track
	$old_this_track = $this_track;

	initialize_chain_setup_vars();
	add_paths_for_main_tracks();
	$debug and say "The graph is:\n$g";
	add_paths_for_recording();
	$debug and say "The graph is:\n$g";
	add_paths_for_null_input_tracks();
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

	# now we have processed graph, we can remove temp tracks

	$this_track = $old_this_track;

	write_chains(); 

	remove_temporary_tracks();
	track_unmemoize();

	1; # used to sense a chain setup ready to run
}
sub remove_temporary_tracks {
	map { $_->remove  } grep{ $_->group eq 'Temp'} Audio::Nama::Track::all();
	$this_track = $old_this_track;
}
sub initialize_chain_setup_vars {

	@io = (); 			# IO object list
	$g = Graph->new(); 	
	%inputs = %outputs = %post_input = %pre_output = ();
	@input_chains = @output_chains = @post_input = @pre_output = ();
	undef $chain_setup;
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
	my @tracks = Audio::Nama::Track::all();

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

	} grep{ (ref $_) !~ /Slave/  # don't record slave tracks
			and $_->rec_status eq 'REC' 
			and not $_->group eq 'null'   # nor null-input tracks
			and not $_->group eq 'Mixdown'# nor Mixdown track
			and not $_->rec_defeat        # nor rec-defeat tracks
	} @tracks;
}

sub input_node { $_[0].'_in' }
sub output_node {$_[0].'_out'}
	

sub add_paths_for_null_input_tracks {
	$debug2 and say "&add_paths_for_null_tracks";

	map{ $g->add_path('null_in', $_->name, 'Master') }
 	grep{ $_->rec_status eq 'REC' } 
	map{$tn{$_}} 	# convert to Track objects
	$Audio::Nama::Group::by_name{null}->tracks; # list of Track names
}

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
			output_node($tn{Master}->send_type));
 

}
sub add_paths_for_mixdown_handling {
	$debug2 and say "&add_paths_for_mixdown_handling";

	if ($tn{Mixdown}->rec_status eq 'REC'){
		my @p = (($mastering_mode ? 'Boost' : 'Master'), ,'Mixdown', 'wav_out');
		$g->add_path(@p);
		$g->set_vertex_attributes('Mixdown', {
		  format	=> 
			signal_format($mix_to_disk_format,$tn{Mixdown}->width),
		  chain_id			=> "Mixdown" }); 
		# no effects will be applied because effects are on chain 2
												 
	# Mixdown handling - playback
	
	} elsif ($tn{Mixdown}->rec_status eq 'MON'){
			my @e = qw(wav_in Mixdown soundcard_out);
			$g->add_path(@e);
			$g->set_vertex_attributes('Mixdown', {
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
	my $attr = $g->get_edge_attributes(@$edge);
	$debug and say "found edge attributes: ",yaml_out($attr) if $attr;

	my $vattr = $g->get_vertex_attributes($edge->[0]);
	$debug and say "found vertex attributes: ",yaml_out($vattr) if $vattr;

	# loop  fields: n: track->n, j: 'a' (counter)
	$attr->{chain_id} //= 'J'.$vattr->{n}. 
		( $vattr->{j} eq 'a' ? ($vattr->{j}++,''): ++$vattr->{j});
	my @direction = qw(input output);
	map{ 
		my $direction = shift @direction;
		my $class = Audio::Nama::IO::get_class($_, $direction);
		my $attrib = {%$vattr, %$attr};
		$attrib->{endpoint} //= $_ if Audio::Nama::Graph::is_a_loop($_); 
		$debug and say "non-track: $_, class: $class, chain_id: $attrib->{chain_id},",
 			"device_id: $attrib->{device_id}";
		$class->new($attrib ? %$attrib : () ) } @$edge;
		# we'd like to $class->new(override($edge->[0], $edge)) } @$edge;
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
				chain_id => $tn{$name}->n,
				override($name, $edge));
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
	my $sf = join_path(&project_dir, $chain_setup_file);
	open my $setup, ">$sf";
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
		my $project_file = join_path(&project_dir , $chain_setup_file);
		eval_iam("cs-disconnect") if eval_iam("cs-connected");
		eval_iam("cs-remove") if eval_iam("cs-selected");
		eval_iam("cs-load ". $project_file);
		eval_iam("cs-select ". $project_file); # needed by Audio::Ecasound, but not Net-ECI !!
		$debug and map{eval_iam($_)} qw(cs es fs st ctrl-status);
}

sub arm {

	# now that we have reconfigure_engine(), use is limited to 
	# - exiting preview
	# - automix	
	
	$debug2 and print "&arm\n";
	exit_preview_mode();
	#adjust_latency();
	if( generate_setup() ){ connect_transport() };
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

	if ( $current eq $old){
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
		print STDOUT Audio::Nama::Text::show_tracks_extra_info();
		connect_transport();
# 		eval_iam("setpos $old_pos") if $old_pos; # temp disable
# 		start_transport() if $was_running and ! $will_record;
		$ui->flash_ready;
		1; }
	else {	my $setup = join_path( project_dir(), $chain_setup_file);
			unlink $setup if -f $setup; }

}

		
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
	load_ecs(); 
	eval_iam("cs-selected") and	eval_iam("cs-is-valid")
		or print("Invalid chain setup, engine not ready.\n"),return;
	find_op_offsets(); 
	apply_ops();
	eval_iam('cs-connect');
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
	} $main->tracks;


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
	print "engine is ", eval_iam("engine-status"), "\n\n"; 

	sleep 1; # time for engine to stabilize
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
	print("transport still running, can't cleanup"),return if transport_running();
	if( my (@files) = new_files_were_recorded() ){
		say join $/, "Now reviewing your recorded files...", (@files);
		(grep /Mixdown/, @files) ? command_process('mixplay') : post_rec_configure();
	reconfigure_engine();
	}
}
sub post_rec_configure {

		$ui->global_version_buttons(); # recreate
		$main->set( rw => 'MON');
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
	$ui->add_effect_gui(\%p);
	if( eval_iam("cs-is-valid") ){
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
	
	my $cmd = "c-select $n";
	$debug and print "cmd: $cmd$/";
	eval_iam($cmd);
	#print "selected chain: ", eval_iam("c-selected"), $/; 

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
		$index = ctrl_index( $id );
		my $cmd = "c-select $n";
		#print "cmd: $cmd$/";
		eval_iam($cmd);
		# print "selected chain: ", eval_iam("c-selected"), $/; # Ecasound bug
		eval_iam("cop-select ". ($offset{$n} + $index));
		#print "selected operator: ", eval_iam("cop-selected"), $/;
		eval_iam("cop-remove");
		$debug and eval_iam("cs");

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

	# do nothing if cop_id has been issued
	return $p{cop_id} if $p{cop_id};

	local $cop_id = $magical_cop_id if $magical_cop_id;

	# make entry in %cops with chain, code, display-type, children

	my ($n, $type, $parent_id, $parameter)  = 
		@p{qw(chain type parent_id parameter)};
	my $i = $effect_i{$type};


	$debug and print "Issuing a cop_id for track $n: $cop_id\n";

	$cops{$cop_id} = {chain => $n, 
					  type => $type,
					  display => $effects[$i]->{display},
					  owns => [] }; 

	$p->{cop_id} = $cop_id;

	# set defaults
	
	if (! $p{values}){
		my @vals;
		$debug and print "no settings found, loading defaults if present\n";
		my $i = $effect_i{ $cops{$cop_id}->{type} };
		
		# don't initialize first parameter if operator has a parent
		# i.e. if operator is a controller
		
		for my $p ($parent_id ? 1 : 0..$effects[$i]->{count} - 1) {
		
			my $default = $effects[$i]->{params}->[$p]->{default};
			push @vals, $default;
		}
		$debug and print "copid: $cop_id defaults: @vals \n";
		$copp{$cop_id} = \@vals;
	}

	if ($parent_id) {
		$debug and print "parent found: $parent_id\n";

		# store relationship
		$debug and print "parent owns" , join " ",@{ $cops{$parent_id}->{owns}}, "\n";

		push @{ $cops{$parent_id}->{owns}}, $cop_id;
		$debug and print join " ", "my attributes:", (keys %{ $cops{$cop_id} }), "\n";
		$cops{$cop_id}->{belongs_to} = $parent_id;
		$debug and print join " ", "my attributes again:", (keys %{ $cops{$cop_id} }), "\n";
		$debug and print "parameter: $parameter\n";

		# set fx-param to the parameter number, which one
		# above the zero-based array offset that $parameter represents
		
		$copp{$cop_id}->[0] = $parameter + 1; 
		
 		# find position of parent and insert child immediately afterwards

 		my $end = scalar @{ $ti{$n}->ops } - 1 ; 
 		for my $i (0..$end){
 			splice ( @{$ti{$n}->ops}, $i+1, 0, $cop_id ), last
 				if $ti{$n}->ops->[$i] eq $parent_id
 		}
	}
	else { push @{$ti{$n}->ops }, $cop_id; } 

	# set values if present
	
	$copp{$cop_id} = $p{values} if $p{values};

	$cop_id++; # return value then increment
}

sub effect_update_copp_set {

	my ($id, $param, $val) = @_;
	effect_update( @_ );
	$copp{$id}->[$param] = $val;
}
	

sub effect_update {

	# update the parameters of the Ecasound chain operator
	# referred to by a Nama operator_id
	
	# (why not use this routine to update %copp values as
	# well?)
	
	#$debug2 and print "&effect_update\n";
	my $es = eval_iam("engine-status");
	$debug and print "engine is $es\n";
	return if $es !~ /not started|stopped|running/;

	my ($id, $param, $val) = @_;
	$param++; # so the value at $p[0] is applied to parameter 1
	my $chain = $cops{$id}{chain};

	carp("effect $id: non-existent chain\n"), return
		unless $chain;

	$debug and print "chain $chain id $id param $param value $val\n";

	# $param is zero-based. 
	# %copp is  zero-based.

	return if $ti{$chain}->rec_status eq "OFF"; 

	# above will produce a wrong result if the user changes track status
	# while the engine is running BUG

	return if $ti{$chain}->name eq 'Mixdown' and 
			  $ti{$chain}->rec_status eq 'REC';

	# above is irrelevant the way that mixdown is now
	# implemented DEPRECATED
	
 	$debug and print join " ", @_, "\n";	

	my $old_chain = eval_iam('c-selected');
	eval_iam("c-select $chain");

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
	eval_iam("c-select $old_chain");
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

	my $resolution = 40; # number of steps per second
	my $steps = $seconds * $resolution;
	my $wink  = 1/$resolution;
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
	my $from  = 0;
	fade( $id, 0, $from, $to, $fade_time + 0.2);
}
sub fadeout {
	my $id    = shift;
	my $from  =	$copp{$id}[0];
	my $to	  = 0;
	fade( $id, 0, $from, $to, $fade_time );
}

sub find_op_offsets {

	$debug2 and print "&find_op_offsets\n";
	eval_iam('c-select-all');
		#my @op_offsets = split "\n",eval_iam("cs");
		my @op_offsets = grep{ /"\d+"/} split "\n",eval_iam("cs");
		shift @op_offsets; # remove comment line
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
 		next if $ti{$n}->rec_status eq "OFF" ;
		#next if $n == 2; # no volume control for mix track
		#next if ! defined $offset{$n}; # for MIX
 		#next if ! $offset{$n} ;

	# controllers will follow ops, so safe to apply all in order
		for my $id ( @{ $ti{$n}->ops } ) {
		apply_op($id);
		}
	}
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
sub new_plugins {
	my $effects_cache = join_path(&project_root, $effects_cache_file);
	my $path = ladspa_path();
	
	my @filenames;
	for my $dir ( split ':', $path){
		opendir DIR, $dir or carp "failed to open directory $dir: $!\n";
		push @filenames,  map{"$dir/$_"} grep{ /.so$/ } readdir DIR;
		closedir DIR;
	}
	push @filenames, '/usr/local/share/ecasound/effect_presets',
                 '/usr/share/ecasound/effect_presets',
                 "$ENV{HOME}/.ecasound/effect_presets";
	my $effmod = modified($effects_cache);
	my $latest;
	map{ my $mod = modified($_);
		 $latest = $mod if $mod > $latest } @filenames;

	$latest > $effmod
}

sub modified {
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

	# first save palette to project_dir/palette.yml
	
	$debug and print "saving palette\n";
	$ui->save_palette;

	save_effect_chains();

	# do nothing more if only Master and Mixdown
	
	if (scalar @Audio::Nama::Track::all == 2 ){
		print "No user tracks, skipping...\n";
		return;
	}

	my $file = shift; # mysettings

	# remove null keys in %cops and %copp
	
	delete $cops{''};
	delete $copp{''};

	$file = $file || $state_store_file;
	$file = join_path(&project_dir, $file) unless $file =~ m(/); 
	$file =~ /\.yml$/ or $file .= '.yml';	
	# print "filename base: $file\n";
	print "\nSaving state as $file\n";

# prepare tracks for storage

@tracks_data = (); # zero based, iterate over these to restore

$debug and print "copying tracks data\n";

map { push @tracks_data, $_->hashref } Audio::Nama::Track::all();
# print "found ", scalar @tracks_data, "tracks\n";

# delete unused fields
map { my $t = $_;
			map{ delete $t->{$_} } 
				qw(ch_r ch_m source_select send_select jack_source jack_send);
} @tracks_data;

@bus_data = (); # 
map{ push @bus_data, $_->hashref } 
	grep{ $_->name !~ /Main|Null/} Audio::Nama::Bus::all();

# prepare marks data for storage (new Mark objects)

@marks_data = ();
$debug and print "copying marks data\n";
map { push @marks_data, $_->hashref } Audio::Nama::Mark::all();

$debug and print "copying groups data\n";
@groups_data = ();
map { push @groups_data, $_->hashref } Audio::Nama::Group::all();

$debug and print "copying bus data\n";


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
sub restore_effect_chains {

	# but don't overwrite them if already present

	assign_var(join_path(project_root(), $effect_chain_file), qw(%effect_chain))
		unless keys %effect_chain; 
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

	# remove empty key hash lines # YAML::Tiny bug
	$yaml = join $/, grep{ ! /^\s*:/ } split $/, $yaml;

	# rewrite obsolete null hash/array substitution
	$yaml =~ s/~NULL_HASH/{}/g;
	$yaml =~ s/~NULL_ARRAY/[]/g;

	# rewrite %cops 'owns' field to []
	
	$yaml =~ s/owns: ~/owns: []/g;

	# restore persistent variables

	assign_var($yaml, @persistent_vars );

	restore_effect_chains();

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

	#  destroy and recreate all groups

	Audio::Nama::Group::initialize();	
	map { Audio::Nama::Group->new( %{ $_ } ) } @groups_data;  
	create_groups(); # make sure we have them all

	# restore user buses
	
	map{ my $class = $_->{class}; Audio::Nama::Bus->new( %$_ ) } @bus_data;
	
	# restore user tracks
	
	my $did_apply = 0;

	map{ 
		my %h = %$_; 
		my $track = Audio::Nama::Track->new( %h ) ; # initially Audio::Nama::Track 
		if ( $track->class ){ bless $track, $track->class } # current scheme
	} @tracks_data;

	$ui->create_master_and_mix_tracks();

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
	print "none muted\n";
		@already_muted = grep{ $_->old_vol_level} 
                         map{ $tn{$_} } 
						 Audio::Nama::Track::user();
	print join " ", "muted", map{$_->name} @already_muted;
	}

	# mute all tracks
	map { $this_track = $tn{$_}; $this_track->mute(1) } Audio::Nama::Track::user();

    $this_track = $current_track;
    $this_track->unmute(1);
	$soloing = 1;
}

sub all {
	
	my $current_track = $this_track;
	# unmute all tracks
	map { $this_track = $tn{$_}; $this_track->unmute(1) } Audio::Nama::Track::user();

	# re-mute previously muted tracks
	if (@already_muted){
		map { $_->mute(1) } @already_muted;
	}

	# remove listing of muted tracks
	
	@already_muted = ();
	$this_track = $current_track;
	$soloing = 0;
	
}

sub show_chain_setup {
	$debug2 and print "&show_chain_setup\n";
	my $setup = join_path( project_dir(), $chain_setup_file);
	say("No tracks to record or play."), return unless -f $setup;
	my $chain_setup;
	io( $setup ) > $chain_setup; 
	pager( $chain_setup );
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
	my $user_input = join " ", @_;
	return if $user_input =~ /^\s*$/;
	$debug and print "user input: $user_input\n";
	my ($cmd, $predicate) = ($user_input =~ /([\S]+?)\b(.*)/);
	if ($cmd eq 'for' 
			and my ($bunchy, $do) = $predicate =~ /\s*(.+?)\s*;(.+)/){
		$debug and print "bunch: $bunchy do: $do\n";
		my ($do_part, $after) = $do =~ /(.+?);;(.+)/;
		$do = $do_part if $do_part;
		my @tracks;
		if ( lc $bunchy eq 'all' ){
			$debug and print "special bunch: all\n";
			@tracks = Audio::Nama::Track::user();
		} elsif ( lc $bunchy eq 'rec' ){
			$debug and print "special bunch: rec\n";
			@tracks = grep{$tn{$_}->rec_status eq 'REC'} Audio::Nama::Track::user();
		} elsif ( my $group = $Audio::Nama::Group::by_name{$bunchy}){
			@tracks = $group->tracks;
		} elsif ( lc $bunchy eq 'mon' ){
			$debug and print "special bunch: mon\n";
			@tracks = grep{$tn{$_}->rec_status eq 'MON'} Audio::Nama::Track::user();
		} elsif ( lc $bunchy eq 'off' ){
			$debug and print "special bunch: off\n";
			@tracks = grep{$tn{$_}->rec_status eq 'OFF'} Audio::Nama::Track::user();
		} elsif ($bunchy =~ /\s/  # multiple identifiers
			or $tn{$bunchy} 
			or $bunchy !~ /\D/ and $ti{$bunchy}){ 
			$debug and print "multiple tracks found\n";
			@tracks = grep{ $tn{$_} or ! /\D/ and $ti{$_} }
				split " ", $bunchy;
			$debug and print "multitracks: @tracks\n";
		} elsif ( $bunch{$bunchy} and @tracks = @{$bunch{$bunchy}}  ) {
			$debug and print "bunch tracks: @tracks\n";
 		} else { say "$bunchy: no matching bunch identifier found" }
		for my $t(@tracks) {
			command_process("$t; $do");
		}
		command_process($after) if $after;
	} elsif ($cmd eq 'eval') {
			$debug and print "Evaluating perl code\n";
			pager( eval $predicate );
			print "\n";
			$@ and print "Perl command failed: $@\n";
	}
	elsif ( $cmd eq '!' ) {
			$debug and print "Evaluating shell commands!\n";
			#system $predicate;
			my $output = qx( $predicate );
			#print "length: ", length $output, $/;
			pager($output); 
			print "\n";
	} else {


		my @user_input = split /\s*;\s*/, $user_input;
		map {
			my $user_input = $_;
			my ($cmd, $predicate) = ($user_input =~ /([\S]+)(.*)/);
			$debug and print "cmd: $cmd \npredicate: $predicate\n";
			if ($cmd eq 'eval') {
				$debug and print "Evaluating perl code\n";
				pager( eval $predicate);
				print "\n";
				$@ and print "Perl command failed: $@\n";
			} elsif ($cmd eq '!') {
				$debug and print "Evaluating shell commands!\n";
				my $output = qx( $predicate );
				#print "length: ", length $output, $/;
				pager($output); 
				print "\n";
			} elsif ($tn{$cmd}) { 
				$debug and print qq(Selecting track "$cmd"\n);
				$this_track = $tn{$cmd};
				my $c = q(c-select ) . $this_track->n; 
				eval_iam( $c ) if eval_iam( 'cs-connected' );
				$predicate !~ /^\s*$/ and $parser->command($predicate);
			} elsif ($cmd =~ /^\d+$/ and $ti{$cmd}) { 
				$debug and print qq(Selecting track ), $ti{$cmd}->name, $/;
				$this_track = $ti{$cmd};
				my $c = q(c-select ) . $this_track->n; 
				eval_iam( $c );
				$predicate !~ /^\s*$/ and $parser->command($predicate);
			} elsif ($iam_cmd{$cmd}){
				$debug and print "Found Iam command\n";
				my $result = eval_iam($user_input);
				pager( $result );  
			} else {
				$debug and print "Passing to parser\n", $_, $/;
				#print 1, ref $parser, $/;
				#print 2, ref $Audio::Nama::parser, $/;
				# both print
				defined $parser->command($_) 
					or print "Bad command: $_\n";
			}    
		} @user_input;
	}
	
	$ui->refresh; # in case we have a graphic environment
}
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


{ my $fake_jack_lsp = q(system:capture_1
   alsa_pcm:capture_1
        properties: output,physical,terminal,
system:capture_2
   alsa_pcm:capture_2
        properties: output,physical,terminal,
system:playback_1
   alsa_pcm:playback_1
        properties: input,physical,terminal,
system:playback_2
   alsa_pcm:playback_2
        properties: input,physical,terminal,
Horgand:out_1
        properties: output,terminal,
Horgand:out_2
        properties: output,terminal,
);

sub jack_update {
	# cache current JACK status
	if    ( $opts{A} ){ $jack_running = 0  }
	elsif ( $opts{J} ){ $jack_running = 1  }
	else  { $jack_running = jack_running() }
	$jack_lsp = $opts{J} ? $fake_jack_lsp : qx(jack_lsp -Ap 2> /dev/null); 
	%jack = %{jack_ports()} if $jack_running;
}
}
sub jack_client {

	# returns true if client and direction exist
	# returns number of client ports
	
	my ($name, $direction)  = @_;

	# synth:in_1 input
	# synth input
	# aeolus:out.R
	
	my $port;
	($name, $port) = $name =~ /^([^:]+):?(.*)/;

	# currently we ignore port

	$jack{$name}{$direction};
}

sub jack_ports {
	$jack_running or return;
	my $j = $jack_lsp; 
	#return if $j =~ /JACK server not running/;

	# convert to single lines

	$j =~ s/\n\s+/ /sg;

	# system:capture_1 alsa_pcm:capture_1 properties: output,physical,terminal,
	my %jack = ();

	map{ 
		my ($direction) = /properties: (input|output)/;
		s/properties:.+//;
		my @ports = /
			\s* 			# zero or more spaces
			([^:]+:[^:]+?) # non-colon string, colon, non-greey non-colon string
			(?=[-+.\w]+:|\s+$) # zero-width port name or spaces to end-of-string
		/gx;
		map { 
				s/ $//; # remove trailing space
				$jack{ $_ }{ $direction }++;
				my ($client, $port) = /(.+?):(.+)/;
				$jack{ $client }{ $direction }++;
				my ($port_prefix) = /:(.+?)\d+$/;
				$jack{ $client }{ $direction.'_prefix' } = $port_prefix;

		 } @ports;

	} split "\n",$j;
	#print yaml_out \%jack;
	\%jack
}
	

sub automix {

	#use Smart::Comments '###';
	# add -ev to summed signal
	my $ev = add_effect( { chain => $tn{Master}->n, type => 'ev' } );
	### ev id: $ev

	# turn off audio output
	
	$main_out = 0;

	### Status before mixdown:

	command_process('show');

	### reduce track volume levels  to 10%
	
	command_process( 'for mon; vol/10');

	#command_process('show');

	generate_setup('automix'); # pass a bit of magic
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
		command_process( 'for mon; vol*10');
		$main_out = 1;
		return;
	}

	### apply multiplier to individual tracks

	command_process( "for mon; vol*$multiplier" );

	# $main_out = 1; # mixdown will turn off and turn on main out
	
	### mixdown
	command_process('mixdown; arm; start');

	### turn on audio output

	# command_process('mixplay'); # rec_cleanup does this
	# automatically

	#no Smart::Comments;
	
}

sub master_on {

	return if $mastering_mode;
	
	# set $mastering_mode	
	
	$mastering_mode++;

	# create mastering tracks if needed
	
	# (no group membership needed)

	if ( ! $tn{Eq} ){  
	
		my $old_track = $this_track;
		add_mastering_tracks();
		add_mastering_effects();
		$this_track = $old_track;
	} else { unhide_mastering_tracks() }
	
}
sub master_off {

	$mastering_mode = 0;
	hide_mastering_tracks();
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

	command_process("append_effect $eq");

	$this_track = $tn{Low};

	command_process("append_effect $low_pass");
	command_process("append_effect $compressor");
	command_process("append_effect $spatialiser");

	$this_track = $tn{Mid};

	command_process("append_effect $mid_pass");
	command_process("append_effect $compressor");
	command_process("append_effect $spatialiser");

	$this_track = $tn{High};

	command_process("append_effect $high_pass");
	command_process("append_effect $compressor");
	command_process("append_effect $spatialiser");

	$this_track = $tn{Boost};
	
	command_process("append_effect $limiter"); # insert after vol
}

sub unhide_mastering_tracks {
	map{ $tn{$_}->set(hide => 0)} @mastering_track_names;
}

sub hide_mastering_tracks {
	map{ $tn{$_}->set(hide => 1)} @mastering_track_names;
 }
		
# vol/pan requirements of mastering tracks

{ my %volpan = (
	Eq => {},
	Low => {},
	Mid => {},
	High => {},
	Boost => {vol => 1},
);

sub need_vol_pan {
	my ($track_name, $type) = @_;
	return 1 unless $volpan{$track_name};
	return 1 if $volpan{$track_name}{$type};
	return 0;
} }
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
	my $orig = $this_track;
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
	my ($name, $type, $id) = @_;
	if ($Audio::Nama::Group::by_name{$name} or $tn{$name}){
		say qq(group, bus, or track "$name" already exists. Skipping."), return;
	}
	Audio::Nama::SubBus->new( 
		name => $name, 
		send_type => $type // 'track',
		send_id	 => $id // $name,
		)
	or carp("can't create bus!\n"), return;
	Audio::Nama::Group->new( name => $name, rw => 'REC');
	# create mix track
	
	Audio::Nama::add_track($name, 	source_type => 'track', 
						source_id 	=> $name,
						rec_defeat 	=> 1,
						);
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

	Audio::Nama::Group->new( name => $name, rw => 'REC');
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

sub new_effect_chain_name {
	my $name = '_'.$this_track->name . '_';
	my $i;
	map{ my ($j) = /_(\d+)$/; $i = $j if $j > $i; }
	@{ $this_track->effect_chain_stack }, 
		grep{/$name/} keys %effect_chain;
	$name . ++$i
}

# too many functions in push and pop!!

sub push_effect_chain {
	say("no effects to store"), return unless $this_track->fancy_ops;
	my %vals = @_; 
	###my $add_name = $vals{add}; # undef in case of bypass # disabled!
	my $save_name   = $vals{save} || new_effect_chain_name();
	#$debug and say "add: $add_name save: $save_name"; 
	new_effect_chain( $save_name ); # current track effects
	push @{ $this_track->effect_chain_stack }, $save_name;
	map{ remove_effect($_)} $this_track->fancy_ops;
	###add_effect_chain($add_name) if $add_name; # disabled!
	#say "save name $save_name";
	$save_name;
}

sub pop_effect_chain { # restore previous, save current as name if supplied
	my $save_name = shift;
	my $previous = pop @{$this_track->effect_chain_stack};
	say ("no previous effect chain"), return unless $previous;
	if($save_name){ 
		push_effect_chain( save => $save_name, add => $previous);
	} 
	else { 
		map{ remove_effect($_)} $this_track->fancy_ops;
		add_effect_chain($previous);
	}
	delete $effect_chain{$previous};
}
sub uncache { 
	my $t = $this_track;
	# skip unless MON;
	my $cm = $t->cache_map;
	my $v = $t->monitor_version;
	if(is_cached()){
		# blast away any existing effects, TODO: warn or abort	
		say $t->name, ": removing effects (except vol/pan)" if $t->fancy_ops;
		map{ remove_effect($_)} $t->fancy_ops;
		$t->set(active => $cm->{$v}{original});
		print $t->name, ": setting uncached version ", $t->active, $/;
		add_effect_chain($cm->{$v}{effect_chain});
	} 
	else { print $t->name, ": version $v is not cached\n"}
}
sub is_cached {
	my $cm = $this_track->cache_map;
	$cm->{$this_track->monitor_version}
}
	

sub replace_effects { is_cached() ? uncache() : pop_effect_chain()}

sub new_effect_chain {
	my ($name, @ops) = @_;
#	say "name: $name, ops: @ops";
	@ops or @ops = $this_track->fancy_ops;
	$effect_chain{$name} = { 
					ops 	=> \@ops,
					type 	=> { map{$_ => $cops{$_}{type} 	} @ops},
					params	=> { map{$_ => $copp{$_} 		} @ops},
	}
}

sub add_effect_chain {
	my $name = shift;
	say ("$name: effect chain does not exist"), return 
		if ! $effect_chain{$name};
	map {  $magical_cop_id = $_ unless $cops{$_}; # try to reuse cop_id
			command_process( join " ", 
				'add_effect',
				$effect_chain{$name}{type}{$_}, 
				@{$effect_chain{$name}{params}{$_}});
			$magical_cop_id = undef;
	} @{$effect_chain{$name}{ops}};
			
}	
sub cleanup_exit {
 	remove_small_wavs();
 	kill 15, ecasound_pid() if $sock;  	
	$term->rl_deprep_terminal();
	CORE::exit; 
}
sub cache_track {
	print($this_track->name, ": track caching requires MON status.\n\n"), 
		return unless $this_track->rec_status eq 'MON';
	print($this_track->name, ": no effects to cache!  Skipping.\n\n"), 
		return unless $this_track->fancy_ops;
 	initialize_chain_setup_vars();
	my $orig = $this_track; 
	my $orig_version = $this_track->monitor_version;
	my $cooked = $this_track->name . '_cooked';
	Audio::Nama::CacheRecTrack->new(
		width => 2,
		name => $cooked,
		group => 'Temp',
		target => $this_track->name,
	);
	$g->add_path( 'wav_in',$orig->name, $cooked, 'wav_out');
	add_paths_for_sub_buses();  # we will prune unneeded ones
	Audio::Nama::Graph::expand_graph($g); # array ref
	Audio::Nama::Graph::add_inserts($g);
	process_routing_graph(); 
	write_chains();
	remove_temporary_tracks();
	connect_transport('no_transport_status')
		or say ("Couldn't connect engine! Skipping."), return;
	say $/,$orig->name,": length ". d2($length). " seconds";
	say "Starting cache operation. Please wait.";
	eval_iam("cs-set-length $length");
	eval_iam("start");
	sleep 2; # time for transport to stabilize
	while( eval_iam('engine-status') ne 'finished'){ 
	print q(.); sleep 2; update_clock_display() } ; print " Done\n";
	$this_track = $orig;
	my $name = $this_track->name;
	my @files = grep{/$name/} new_files_were_recorded();
	if (@files ){ 
		$debug and say "updating track cache_map";
		#say "cache map",yaml_out($this_track->cache_map);
		my $cache_map = $this_track->cache_map;
		$cache_map->{$this_track->last} = { 
			original 			=> $orig_version,
			effect_chain	=> push_effect_chain(), # bypass
		};
		pop @{$this_track->effect_chain_stack};
		#say "cache map",yaml_out($this_track->cache_map);
		say qq(Saving effects for cached track "$name".
'replace' will restore effects and set version $orig_version\n);
		post_rec_configure();
	} else { say "track cache operation failed!"; }
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

sub add_insert_cooked {
	my ($send_id, $return_id) = @_;

	my $old_this_track = $this_track;
	my $t = $Audio::Nama::this_track;
	my $name = $t->name;
	#$t->remove_insert;
	my $i = {
		insert_type => 'cooked',
		send_type 	=> Audio::Nama::dest_type($send_id),
		send_id	  	=> $send_id,
		return_type 	=> Audio::Nama::dest_type($return_id),
		return_id	=> $return_id,
		wetness		=> 100,
	};
	# default to return from same JACK client or adjacent soundcard channels
	if (! $i->{return_id}){
		$i->{return_type} = $i->{send_type};
		$i->{return_id} =  $i->{send_id} if $i->{return_type} eq 'jack_client';
		$i->{return_id} =  $i->{send_id} + 2 if $i->{return_type} eq 'soundcard';
	}
	# default to return via same system (soundcard or JACK)

	
	$t->set(inserts => $i); 1;

	# we slave the wet track to the original track so that
	# we know the external output (if any) will be identical
	
	my $wet = Audio::Nama::SlaveTrack->new( 
				name => "$name\_wet",
				target => $name,
				group => 'Insert',
				rw => 'REC',
				hide => 1,
			);
	# in the graph we will override the input with the insert's return source

	# we slave the dry track to the original track so that
	# we know the external output (if any) will be identical
	
	my $dry = Audio::Nama::SlaveTrack->new( 
				name => "$name\_dry", 
				target => $name,
				group => 'Insert',
				hide => 1,
				rw => 'REC');

	# the input fields will be ignored, since the track will get input
	# via the loop device track_insert
	
	$i->{dry_vol} = $dry->vol;
	$i->{wet_vol} = $wet->vol;
	
	$i->{tracks} = [ map{ $_->name } ($wet, $dry) ];
	$this_track = $old_this_track;
}

sub ecasound_get_info {
	my ($path, $command) = @_;
	eval_iam('cs-disconnect') if eval_iam('cs-connected');
	eval_iam('cs-add gl');
	eval_iam('c-add g');
	eval_iam('ai-add ' . $path);
	eval_iam('ao-add null');
	eval_iam('cs-connect');
	eval_iam('engine-launch');
	eval_iam('ai-select '. $path);
	my $result = eval_iam($command);
	eval_iam('cs-disconnect');
	eval_iam('cs-remove gl');
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
# 	$sn_dump->configure(
# 		-text => q(Dump state),
# 		-command => sub{ print &status_vars });
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
	my $rule = $rec_file;
	my $status = $rule->status;
	my $oid_button = $transport_frame->Button( );
	$oid_button->configure(
		-text => 'Preview',
		-command => sub { 
			$rule->set(status => ! $rule->status);
			$oid_button->configure( 
		-background => 
				$rule->status ? $old_bg : $namapalette{Preview} ,
		#-activebackground => 
		#		$rule->status ? $old_bg : $namapalette{ActivePreview} ,
		-text => 
				$rule->status ? 'Preview' : 'PREVIEW MODE'
					
					);

			if ($rule->status) { # rec_file enabled
				arm()
			} else { 
				preview();
			}

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
	push @range, "";
	push @range, 1..$tk_input_channels if $n > 2;
	
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
	$ch_m = $track_frame->Menubutton(
					-tearoff => 0,
					# -relief => 'groove',
				);
				for my $v ("off",3..10) {
					$ch_m->radiobutton(
						-label => $v,
						-value => $v,
						-command => sub { 
							return if eval_iam("engine-status") eq 'running';
			#				$ti{$n}->set(rw  => "MON");
							$ti{$n}->send($v);
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
				if ($copp{$vol_id}->[0]) {  # non-zero volume
					$ti{$n}->set(old_vol_level => $copp{$vol_id}->[0]);
					effect_update_copp_set( $vol_id, 0, 0);
					$mute->configure(-background => $namapalette{Mute});
				}
				else {
					effect_update_copp_set($vol_id, 0,$ti{$n}->old_vol_level);
					$ti{$n}->set(old_vol_level => 0);
					$mute->configure(-background => $off);
				}
			}	
		  );

		# Unity

		$unity = $track_frame->Button(
				-command => sub { 
					effect_update_copp_set($vol_id, 0, 100);
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
		$number, $name, $version, $rw, $ch_r, $ch_m, $vol,
			$mute, $unity, $pan, $center, @add_effect, $effects ];

	refresh_track($n);

}

sub remove_track_gui {
 	@_ = discard_object( @_ );
 	my $n = shift;
	#say "&remove_track_gui";
	#say "track $n";
	return unless $track_widget_remove{$n};
	#say "exists";
	my $m = 0;
 	map {$_->destroy  } @{ $track_widget_remove{$n} };
	delete $track_widget_remove{$n};
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

	#return unless $track_widget{$n}; # hidden track
	
	# set the text for displayed fields

	$track_widget{$n}->{rw}->configure(-text => $rec_status);
	$track_widget{$n}->{ch_r}->configure( -text => 
				$n > 2
					? $ti{$n}->source
					:  q() );
	$track_widget{$n}->{ch_m}->configure( -text => $ti{$n}->send);
	$track_widget{$n}->{version}->configure(-text => $ti{$n}->current_version);
	
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
	map{ $ui->refresh_track($_) } map{$_->n} Audio::Nama::Track::all();
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

use Audio::Nama::Track;   

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
		} else { q() }
}

sub show_effects {
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
		"Bypassed effect chains: ".scalar @{ $this_track->effect_chain_stack }.$/
			if @{ $this_track->effect_chain_stack } 
}
	
sub show_region {
	my @lines;
	push @lines, "Start delay: ",
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
	push @fields, "record" if Audio::Nama::really_recording();
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
	return $val if $val;
	$use_placeholders ? q(--) : q() 
}

{
my $format_top = <<TOP;
Track Name      Ver. Setting  Status   Source           Send        Vol  Pan 
=============================================================================
TOP

my $format_picture = <<PICTURE;
@>>   @<<<<<<<<< @>    @<<    @|||| @||||||||||||| @||||||||||||||  @>>  @>> 
PICTURE

sub show_tracks {
    no warnings;
	$^A = $format_top;
    my @tracks = @_;
    map {   formline $format_picture, 
            $_->n,
            $_->name,
            placeholder( $_->current_version ),
			(ref $_) =~ /MasteringTrack/ 
					? placeholder() 
					: lc $_->rw,
            $_->rec_status_display,
            $_->name =~ /Master|Mixdown/ 
					? placeholder() 
					: placeholder($_->source_status),
			placeholder($_->send_status),
			placeholder($copp{$_->vol}->[0]),
			placeholder($copp{$_->pan}->[0]),
            #(join " ", @{$_->versions}),

        } grep{ ! $_-> hide} @tracks;
        
    #write; # using format below
    #$- = 0; # $FORMAT_LINES_LEFT # force header on next output
	
    #1;
    #use warnings;
    #no warnings q(uninitialized);
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

	# remove later ops if engine is connected
	# this will not change the $track->cops list 

	my @ops = @{$track->ops}[$offset..$#{$track->ops}];
	$debug and print "ops to remove and re-apply: @ops\n";
	my $connected = eval_iam('cs-connected');
	if ( $connected ){  
		map{ remove_op($_)} reverse @ops; # reverse order for correct index
	}

	Audio::Nama::Text::t_add_effect( $code, $values );

	$debug and print join " ",@{$track->ops}, $/; 

	my $op = pop @{$track->ops}; 
	# acts directly on $track, because ->ops returns 
	# a reference to the array

	# insert the effect id 
	splice 	@{$track->ops}, $offset, 0, $op;
	$debug and print join " ",@{$track->ops}, $/; 

	if ($connected ){  
		map{ apply_op($_, $n) } @ops;
	}
		
	if ($running){
		eval_iam('start');	
		sleeper(0.3);
		Audio::Nama::unmute();
		$ui->start_heartbeat;
	}
}
sub t_add_effect {
	package Audio::Nama;
	my ($code, $values)  = @_;
	$code = effect_code( $code );	
	$debug and print "code: ", $code, $/;
		my %p = (
			chain => $this_track->n,
			values => $values,
			type => $code,
			);
			#print "adding effect\n";
			$debug and print (yaml_out(\%p));
		add_effect( \%p );
}
sub group_rec { 
	print "Setting group REC-enable. You may record user tracks.\n";
	$main->set( rw => 'REC'); }
sub group_mon { 
	print "Setting group MON mode. No recording on user tracks.\n";
	$main->set( rw => 'MON');}
sub group_off {
	print "Setting group OFF mode. All user tracks disabled.\n";
	$main->set(rw => 'OFF'); } 

sub mixdown {
	print "Enabling mixdown to file.\n";
	$tn{Mixdown}->set(rw => 'REC'); 
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
	$main->set(rw => 'MON')}

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

package Audio::Nama;

### COMMAND LINE PARSER 

$debug2 and print "Reading grammar\n";

$commands_yml = <<'YML';
---
testq:
  what: test
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
  what: toggle rec-defeat
  parameters: none
source:
  type: track
  what: set track source
  short: src r
  parameters: <i_soundcard_channel> | <s_jack_client_name> | 'jack' (opens ports ecasound:trackname_in_N, connects ports listed in trackname.ports if present in project_root dir)
send:
  type: track
  what: set aux send
  short: out aux m
  parameters: <i_soundcard_channel> (3 or above) | <s_jack_client_name>
remove_send:
  type: track
  short: nosend rms
  what: remove aux send
  parameters: none  what: set auxilary track destination
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
cache_track:
  type: track
  short: cache ct
  what: record the post-fader signal as a new version
  parameters: none
group_rec:
  type: group
  short: grec R
  what: rec-enable user tracks
  parameters: none
group_mon:
  type: group
  short: gmon M
  what: rec-disable user tracks
  parameters: none
group_version:
  type: group 
  short: gn gver gv
  what: set group version for monitoring (overridden by track-version settings)
group_off:
  type: group
  short: goff Z 
  what: group OFF mode, exclude all user tracks from chain setup
  parameters: none
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
  short: recall restore retrieve
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
  type: effect
  what: add effect to current track (placed before volume control)
  short: afx
  parameters: <s_effect_code> [ <f_param1> <f_param2>... ]
  example: add_effect amp 6 (LADSPA Simple amp 6dB gain)!nadd_effect var_dali (preset var_dali) Note: no el: or pn: prefix is required
append_effect:
  type: effect
  what: add effect to the end of current track (mainly legacy use)
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
  example: modify_effect V 1 -1 (set effect_id V, parameter 1 to -1)!nmodify_effect V 1 - 10 (reduce effect_id V, parameter 1 by 10)!nset multiple effects/parameters: mfx V 1,2,3 + 0.5 ; mfx V,AC,AD 1,2 3.14
remove_effect:
  type: effect
  what: remove effects from selected track
  short: rfx remove_controller rcl
  parameters: <s_effect_id1> [ <s_effect_id2>...]
add_insert_cooked:
  type: effect 
  short: ainc
  what: add an external post-fader send/return to a track
  parameters: <s_send_id> [<s_return_id>]
set_insert_wetness:
  type: effect 
  short: wet
  what: set wet/dry balance for track insert: 100 = all wet, 0 = all dry
  parameters: <n_wetness>
remove_insert:
  type: effect
  short: rin
  what: remove a track's insert
  parameters: none
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
  what: set bus parameters TODO
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
  what: remove an effect chain definition from the list
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
replace_effects:
  type: effect
  short: replace rep 
  what: restore bypassed track effects
uncache_track:
  type: effect
  short: uncache unc
  what: set uncached track version, restoring effects (if current version is cached)
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
...

YML

$cop_hints_yml = <<'YML';
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
  count: 4
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
YML

%commands = %{ Audio::Nama::yaml_in( $Audio::Nama::commands_yml) };

$Audio::Nama::AUTOSTUB = 1;
$Audio::Nama::RD_TRACE = 1;
$Audio::Nama::RD_ERRORS = 1; # Make sure the parser dies when it encounters an error
$Audio::Nama::RD_WARN   = 1; # Enable warnings. This will warn on unused rules &c.
$Audio::Nama::RD_HINT   = 1; # Give out hints to help fix problems.

$grammar = q(

key: /\w+/
someval: /[\w.+-]+/
sign: '+' | '-' | '*' | '/'
value: /[+-]?([\d_]+(\.\d*)?|\.\d+)([eE][+-]?\d+)?/
op_id: /[A-Z]+/
parameter: /\d+/
last: ('last' | '$' ) 
dd: /\d+/
jack_port: /\w[-+:. \w]+/
name: /\w[\w:,]*\/?/
name2: /[\w\-+:]+/
name3: /\S+/
name4: /\w+/
marktime: /\d+\.\d+/ 
markname: /\w+/ { 	 
	print("$item[1]}: non-existent mark name. Skipping\n"), return undef 
		unless $Audio::Nama::Mark::by_name{$item[1]};
	$item[1];
}
path: /(["'])[\w-\. \/]+$1/
path: /[\w\-\.\/]+/
modifier: 'audioloop' | 'select' | 'reverse' | 'playat' | value
end: /[;\s]*$/ 
help_effect: _help_effect name end { Audio::Nama::Text::help_effect($item{name}) ; 1}
find_effect: _find_effect name3(s) { 
	Audio::Nama::Text::find_effect(@{$item{"name3(s)"}}); 1}
help: _help 'yml' end { Audio::Nama::pager($Audio::Nama::commands_yml); 1}
help: _help name2  { Audio::Nama::Text::help($item{name2}) ; 1}
help: _help end { print $Audio::Nama::help_screen ; 1}
project_name: _project_name end { 
	print "project name: ", $Audio::Nama::project_name, $/; 1}
create_project: _create_project name end { 
	Audio::Nama::Text::t_create_project $item{name} ; 1}
list_projects: _list_projects end { Audio::Nama::list_projects() ; 1}
load_project: _load_project name3 end {
	Audio::Nama::Text::t_load_project $item{name3} ; 1}
save_state: _save_state name end { Audio::Nama::save_state( $item{name}); 1}
save_state: _save_state end { Audio::Nama::save_state(); 1}
get_state: _get_state name end {
 	Audio::Nama::load_project( 
 		name => $Audio::Nama::project_name,
 		settings => $item{name}
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
add_track: _add_track name2(s) end {
	Audio::Nama::add_track(@{$item{'name2(s)'}}); 1}
add_tracks: _add_tracks name2(s) end {
	map{ Audio::Nama::add_track($_)  } @{$item{'name2(s)'}}; 1}
set_track: _set_track 'bus' bus_name end {
	$Audio::Nama::this_track->set( group => $item{bus_name}); 1
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
link_track: _link_track name target project end {
	Audio::Nama::add_track_alias_project($item{name}, $item{target}, $item{project}); 1
}
link_track: _link_track name target end {
	Audio::Nama::add_track_alias($item{name}, $item{target}); 1
}
target: name
project: name
set_region: _set_region beginning ending end { 
	Audio::Nama::set_region( @item{ qw( beginning ending ) } );
	1;
}
set_region: _set_region beginning end { Audio::Nama::set_region( $item{beginning}, 'END' );
	1;
}
remove_region: _remove_region end { Audio::Nama::remove_region(); 1; }
new_region: _new_region beginning ending name(?) end {
	my ($name) = @{$item{'name(?)'}};
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
		$Audio::Nama::this_track->set(playat => $time);
		1;
	} else { print 
	"Shift value is neither decimal nor mark name. Skipping.\n";
	0;
	}
}
start_position:  float | mark_name
float: /\d+\.\d+/
mark_name: name
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
show_chain_setup: _show_chain_setup { Audio::Nama::show_chain_setup(); 1}
show_io: _show_io { Audio::Nama::show_io(); 1}
show_track: _show_track end {
	my $output = Audio::Nama::Text::show_tracks($Audio::Nama::this_track);
	$output .= Audio::Nama::Text::show_effects();
	$output .= Audio::Nama::Text::show_versions();
	$output .= Audio::Nama::Text::show_modifiers();
	$output .= join "", "Signal width: ", Audio::Nama::width($Audio::Nama::this_track->width), "\n";
	$output .= Audio::Nama::Text::show_region();
	$output .= Audio::Nama::Text::show_effect_chain_stack();
	Audio::Nama::pager( $output );
	1;}
show_track: _show_track name end { 
 	Audio::Nama::pager( Audio::Nama::Text::show_tracks( 
	$Audio::Nama::tn{$item{name}} )) if $Audio::Nama::tn{$item{name}};
	1;}
show_track: _show_track dd end {  
	Audio::Nama::pager( Audio::Nama::Text::show_tracks( $Audio::Nama::ti{$item{dd}} )) if
	$Audio::Nama::ti{$item{dd}};
	1;}
group_rec: _group_rec end { Audio::Nama::Text::group_rec(); 1}
group_mon: _group_mon end  { Audio::Nama::Text::group_mon(); 1}
group_off: _group_off end { Audio::Nama::Text::group_off(); 1}
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
source: _source 'jack' end { $Audio::Nama::this_track->set_source('jack'); 1 }
source: _source dd end { $Audio::Nama::this_track->set_source( $item{dd} ); 1 }
source: _source jack_port end { $Audio::Nama::this_track->set_source( $item{jack_port} ); 1 }
source: _source end { 
	my $source = $Audio::Nama::this_track->source;
	my $object = $Audio::Nama::this_track->input_object;
	if ( $source ) { 
		print $Audio::Nama::this_track->name, ": input from $object.\n";
	} else {
		print $Audio::Nama::this_track->name, ": REC disabled. No source found.\n";
	}
	1;
}
send: _send name { $Audio::Nama::this_track->set_send($item{name}); 1}
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
	$Audio::Nama::this_track->set(rec_defeat => !  $Audio::Nama::this_track->rec_defeat);
	print $Audio::Nama::this_track->name, ": WAV record ",
		($Audio::Nama::this_track->rec_defeat ? "disabled" : "enabled"), $/;
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
	Audio::Nama::effect_update_copp_set( $Audio::Nama::this_track->vol, 0, 100);
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
remove_mark: _remove_mark name end { 
	my $mark = $Audio::Nama::Mark::by_name{$item{name}};
	$mark->remove if defined $mark;
	1;}
remove_mark: _remove_mark end { 
	return unless (ref $Audio::Nama::this_mark) =~ /Mark/;
	$Audio::Nama::this_mark->remove;
	1;}
new_mark: _new_mark name end { Audio::Nama::drop_mark $item{name}; 1}
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
name_mark: _name_mark name end {$Audio::Nama::this_mark->set_name( $item{name}); 1}
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
to_mark: _to_mark name end { 
	my $mark = $Audio::Nama::Mark::by_name{$item{name}};
	$mark->jump_here if defined $mark;
	1;}
modify_mark: _modify_mark sign value end {
	my $newtime = eval($Audio::Nama::this_mark->time . $item{sign} . $item{value});
	$Audio::Nama::this_mark->set( time => $newtime );
	print $Audio::Nama::this_mark->name, ": set to ", Audio::Nama::d2( $newtime), "\n";
	Audio::Nama::eval_iam("setpos $newtime");
	1;
	}
modify_mark: _modify_mark value end {
	$Audio::Nama::this_mark->set( time => $item{value} );
	print $Audio::Nama::this_mark->name, ": set to ", Audio::Nama::d2( $item{value}), "\n";
	Audio::Nama::eval_iam("setpos $item{value}");
	1;
	}		
remove_effect: _remove_effect op_id(s) end {
	Audio::Nama::mute();
	map{ print "removing effect id: $_\n"; Audio::Nama::remove_effect( $_ )
	} grep { $_ }  @{ $item{"op_id(s)"}} ;
	Audio::Nama::sleeper(0.5);
	Audio::Nama::unmute();
	1;}
add_controller: _add_controller parent name value(s?) end {
	my $code = $item{name};
	my $parent = $item{parent};
	my $values = $item{"value(s?)"};
	Audio::Nama::Text::t_add_ctrl $parent, $code, $values;
	1;}
parent: op_id
add_effect: _add_effect name value(s?)  end { 
	my $code = $item{name};
	my $values = $item{"value(s?)"};
	my $before = $Audio::Nama::this_track->vol;
	Audio::Nama::Text::t_insert_effect  $before, $code, $values ;
 	1;}
append_effect: _append_effect name value(s?) end {
	my $code = $item{name};
	my $values = $item{"value(s?)"};
 	Audio::Nama::Text::t_add_effect $code, $values;
 	1;}
insert_effect: _insert_effect before name value(s?) end {
	my $before = $item{before};
	my $code = $item{name};
	my $values = $item{"value(s?)"};
	print join ", ", @{$values} if $values;
	Audio::Nama::Text::t_insert_effect  $before, $code, $values;
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
group_version: _group_version end { 
	use warnings;
	no warnings qw(uninitialized);
	print $Audio::Nama::main->version, "\n" ; 1}
group_version: _group_version dd end { 
	my $n = $item{dd};
	$n = undef if $n == 0;
	$Audio::Nama::main->set( version => $n ); 1}
new_bunch: _new_bunch name(s) { Audio::Nama::Text::bunch( @{$item{'name(s)'}}); 1}
list_bunches: _list_bunches end { Audio::Nama::Text::bunch(); 1}
remove_bunches: _remove_bunches name(s) { 
 	map{ delete $Audio::Nama::bunch{$_} } @{$item{'name(s)'}}; 1}
add_to_bunch: _add_to_bunch name(s) end { Audio::Nama::Text::add_to_bunch( @{$item{'name(s)'}});1 }
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
	$Audio::Nama::this_track->ingest( $item{path}, $item{frequency}); 1;
}
import_audio: _import_audio path end {
	$Audio::Nama::this_track->ingest( $item{path}); 1;
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
add_slave_track: _add_slave_track bus_name target end {
	Audio::Nama::add_slave_track( group => $item{bus_name}, target => $item{target} ); 1; } 
bus_name: /[A-Z]\w+/
destination: /\d+/ | /loop,\w+/ | name2
remove_bus: _remove_bus bus_name end {
	print ("$item{bus_name}: no such bus\n"), return 
		unless $Audio::Nama::Bus::by_name{$item{bus_name}};
	$Audio::Nama::Bus::by_name{$item{bus_name}}->remove;
	1;
}
update_send_bus: _update_send_bus bus_name end {
 	Audio::Nama::update_send_bus( $item{bus_name} );
 	1;
}
set_bus: _set_bus { print "stub command, does nothing, sorry.\n"}
list_buses: _list_buses end { Audio::Nama::pager(map{ $_->dump } Audio::Nama::Bus::all()) }
add_insert_cooked: _add_insert_cooked send_id return_id(?) end {
	my $return_id = "@{$item{'return_id(?)'}}";
	my $send_id = $item{send_id};
	Audio::Nama::add_insert_cooked($send_id, $return_id);
	1;
}
send_id: name
return_id: name
set_insert_wetness: _set_insert_wetness parameter end {
	my $p = $item{parameter};
	print ("wetness parameter must be an integer between 0 and 100\n"), return 1
		if ! ($p <= 100 and $p >= 0);
	my $i = $Audio::Nama::this_track->inserts;
	print ("track '",$Audio::Nama::this_track->n, "' has no insert.  Skipping.\n"),
		return 1 unless $i;
	$i->{wetness} = $p;
	Audio::Nama::modify_effect($i->{wet_vol}, 0, undef, $p);
	Audio::Nama::sleeper(0.1);
	Audio::Nama::modify_effect($i->{dry_vol}, 0, undef, 100 - $p);
	1;
}
set_insert_wetness: _set_insert_wetness end {
	my $i = $Audio::Nama::this_track->inserts;
	print ("track ",$Audio::Nama::this_track->n, " has no insert.\n"), return 1 unless $i;
	 print "The insert is ", 
		$i->{wetness}, "% wet, ", (100 - $i->{wetness}), "% dry.\n";
}
remove_insert: _remove_insert end { 
	$Audio::Nama::this_track->remove_insert;
	1;
}
cache_track: _cache_track end { Audio::Nama::cache_track(); 1 }
uncache_track: _uncache_track end { Audio::Nama::uncache(); 1 }
new_effect_chain: _new_effect_chain name op_id(s?) end {
	Audio::Nama::new_effect_chain($item{name}, @{ $item{'op_id(s?)'} });
	1;
}
add_effect_chain: _add_effect_chain name end {
	Audio::Nama::add_effect_chain($item{name});
	1;
}
delete_effect_chain: _delete_effect_chain name(s) end {
	map{ delete $Audio::Nama::effect_chain{$_} } @{ $item{'name(s)'} };
	1;
}
list_effect_chains: _list_effect_chains name(s?) end {
    my @ids = grep{ ! /^_/ } keys %Audio::Nama::effect_chain;
	if (my @frags = @{$item{'name(s?)'}}){
		@ids = grep{ my $id = $_; grep{ $id =~ /$_/} @frags} @ids; 
	}
	map{ my $name = $_;
		print join ' ', "$name:", 
		map{$Audio::Nama::effect_chain{$name}{type}{$_},
			@{$Audio::Nama::effect_chain{$name}{params}{$_}}
		} @{$Audio::Nama::effect_chain{$name}{ops}};
		print "\n";
	} @ids;
	1;
}
bypass_effects:   _bypass_effects end { Audio::Nama::push_effect_chain(); 1}
replace_effects: _replace_effects end {  Audio::Nama::replace_effects(); 1;}
overwrite_effect_chain: _overwrite_effect_chain name end {
	my $name = $item{name};
	print("$name: unknown effect chain.\n"), return if !  $Audio::Nama::effect_chain{$name};
	Audio::Nama::push_effect_chain() if $Audio::Nama::this_track->fancy_ops;
	Audio::Nama::add_effect_chain($name); 1
}
do_script: _do_script name2 end { Audio::Nama::do_script($item{name2});1}
scan: _scan end { print "scanning ", Audio::Nama::this_wav_dir(), "\n"; Audio::Nama::rememoize() }


command: testq
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
command: cache_track
command: group_rec
command: group_mon
command: group_version
command: group_off
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
command: append_effect
command: insert_effect
command: modify_effect
command: remove_effect
command: add_insert_cooked
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
command: replace_effects
command: uncache_track
command: do_script
command: scan
_testq: /testq\b/
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
_mon: /mon\b/
_off: /off\b/ | /z\b/
_rec_defeat: /rec_defeat\b/ | /rd\b/
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
_cache_track: /cache_track\b/ | /cache\b/ | /ct\b/
_group_rec: /group_rec\b/ | /grec\b/ | /R\b/
_group_mon: /group_mon\b/ | /gmon\b/ | /M\b/
_group_version: /group_version\b/ | /gn\b/ | /gver\b/ | /gv\b/
_group_off: /group_off\b/ | /goff\b/ | /Z\b/
_new_bunch: /new_bunch\b/ | /nb\b/
_list_bunches: /list_bunches\b/ | /lb\b/
_remove_bunches: /remove_bunches\b/ | /rb\b/
_add_to_bunch: /add_to_bunch\b/ | /ab\b/
_save_state: /save_state\b/ | /keep\b/ | /save\b/
_get_state: /get_state\b/ | /recall\b/ | /restore\b/ | /retrieve\b/
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
_append_effect: /append_effect\b/
_insert_effect: /insert_effect\b/ | /ifx\b/
_modify_effect: /modify_effect\b/ | /mfx\b/ | /modify_controller\b/ | /mcl\b/
_remove_effect: /remove_effect\b/ | /rfx\b/ | /remove_controller\b/ | /rcl\b/
_add_insert_cooked: /add_insert_cooked\b/ | /ainc\b/
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
_replace_effects: /replace_effects\b/ | /replace\b/ | /rep\b/
_uncache_track: /uncache_track\b/ | /uncache\b/ | /unc\b/
_do_script: /do_script\b/ | /do\b/
_scan: /scan\b/
);


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

   add_insert_cooked,  ainc   - add a post-fader insert to the current track
   remove_insert,      rin    - remove current track's insert
   set_insert_wetness, wet    - set/query insert wetness 
                                example: wet 99 (99% wet, 1% dry)

-  effect chains

   new_effect_chain,   nec    - define a new effect chain
   add_effect_chain,   aec    - add an effect chain to the current track
   delete_effect_chain,dec    - delete an effect chain
   list_effect_chains, lec    - list effect chains and their parameters
   bypass_effects,     bye    - suspend current track effects except vol/pan
   replace_effects,    rep    - restore track effects

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

   for                        - execute commands on several tracks 
                                by name, or by specifying a group or bunch
                                example: for strings; vol +10
                                example: for drumkit congas; mute
                                example: for 3 5; vol * 1.5
                                example: for all; version 5;; show
                                  'show' follows ';;' so executes only once
                
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

$default = <<'FALLBACK_CONFIG';
#
#
#         Nama Configuration file

#         Notes

#         - This configuration file is distinct from
#           Ecasound's configuration file .ecasoundrc . 
#           In most instances the latter is not required.

#        - The format of this file is YAMLish, preprocessed to allow
#           comments.
#
#        - A value _must_ be supplied for each 'leaf' field.
#          For example "mixer_out_format: cd-stereo"
#
#        - A value must _not_ be supplied for nodes, i.e.
#          'device:'. The value for 'device' is the entire indented
#          data structure that follows in subsequent lines.
#
#        - Indents are significant, two spaces indent for
#          each new level of branching
#
#        - Use the tilde symbol '~' to represent a null value
#

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
    signal_format: f32_le,N,frequency
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
mixer_out_format: cd-stereo     	# for ALSA/OSS

# audio file formats

mix_to_disk_format: s16_le,N,frequency,i
raw_to_disk_format: s16_le,N,frequency,i

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

# effects for use in mastering mode

eq: Parametric1 1 0 0 40 0.125 0 0 200 0.125 0 0 600 0.125 0 0 3300 0.125 0

low_pass: lowpass_iir 120 1

mid_pass: bandpass_iir 420 800 1

high_pass: highpass_iir 920 1

compressor: sc4 0 3 16 0 1 3.25 0

spatialiser: matrixSpatialiser 0

limiter: tap_limiter 0 0

# end

# Julien Claassen's Notes on Mastering effect defaults
# 
# The eq: All sections turned off, in case you don't want the
# EQ after all and when you turn them on, you can easily do
# them one at a time. 
# 
# All bands set to minimum width, so you can hear center
# you're going to manipulate clearly. You can always extend.
# But that way - I've discovered - it's more accurate to work.
# The band frequencies are just a basic selection, based on my
# usual starting points.
# 
# The compressor's turned off, but some default values are set for all other 
# params.
# 
# The spatialiser is set to 0: no effect. Same goes for the
# limiter. So you can start out clean and slowly work your way
# from there.

FALLBACK_CONFIG

$default_palette_yml = <<'PALETTE';
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

PALETTE

1;

__END__

=head1 NAME

B<Nama> - Ecasound-based recorder, mixer and mastering system

=head1 SYNOPSIS

B<nama> [I<options>] [I<project_name>]

=head1 DESCRIPTION

B<Nama> is a recorder/mixer application using Ecasound in
the back end to provide multitrack recording, effects
processing, and mastering. Nama includes aux sends, inserts,
buses, regions and time-shifting functions. Full help is
provided, including commands by category, search for
commands or effects by name or by arbitrary string.

By default, Nama starts up a GUI interface with a command
line interface running in the terminal window. The B<-t>
option provides a text-only interface for console
users.

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

Ecasound is configured through use of I<chain setups>. Nama
serves as intermediary generating appropriate chain setups
for recording, playback, mixing, etc. and running the audio
processing engine according to user commands.

Commands for audio processing with Nama/Ecasound fall into
two categories: I<static commands> that influence the chain
setup and I<dynamic commands> that influence the realtime
behavior of the audio processing engine.

=head2 STATIC COMMANDS

Static commands affect I<future> runs of the audio
processing engine. For example, B<rec, mon> and B<off>
determine whether the current track will get its audio
stream from a live source or whether an existing WAV file
will be played back. Nama responds to static commands by
reconfiguring the engine and displaying the updated
track status in text and GUI form.

=head2 DYNAMIC COMMANDS

Once a chain setup is loaded and the engine is launched,
another subset of commands controls the realtime behavior of
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
provides a large subset of Nama's functionality on two
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
scaling hints are automatically detects. Text-entry widgets
are used to enter parameters values for plugins without
hinted ranges.

The text command prompt appears in the terminal window
during GUI operation. Text commands may be issued at any
time.

=head1 TEXT UI

Press the I<Enter> key if necessary to get the following command prompt.

=over 12

C<nama ('h' for help)E<gt>>

=back

You can enter Nama and Ecasound commands directly, Perl code
preceded by C<eval> or shell code preceded by C<!>.

Multiple commands on a single line are allowed if delimited
by semicolons. Usually the lines are split on semicolons and
the parts are executed sequentially, however if the line
begins with C<eval> or C<!> the entire line will be given to
the corresponding interpreter.

You can access command history using up-arrow/down-arrow.

Type C<help> for general help, C<help command> for help with
C<command>, C<help foo> for help with commands containing
the string C<foo>. C<help_effect foo bar> lists all 
plugins/presets/controller containing both I<foo> and
I<bar>. Tab-completion is provided for Nama commands, Ecasound-iam
commands, plugin/preset/controller names, and project names.

=head1 TRACKS

Ecasound deals with audio processing at the level audio and
loop devices, files, and signal-processing chains. Nama
provides tracks, buses, marks and other high-level
abstractions. Chief among these are tracks.
 
Each track has a descriptive name (i.e. vocal) and an
integer track-number assigned when the track is created.
The following paragraphs describes track fields and
their settings.

=head2 WIDTH

Specifying 'mono' means one-channel input and recording the
raw signal as a mono WAV file. The mono signal is duplicated
to a stereo signal with pan in the default mixer
configuration.

Specifying 'stereo' means two-channel input with recording
as a stereo WAV file.

Specifying N channels ('set width N') means N-channel input
with recording as an N-channel WAV file.

=head2 VERSION NUMBER

Multiple WAV files can be recorded for each track. These are
identified by a version number that increments with each
recording run, i.e. F<sax_1.wav>, F<sax_2.wav>, etc.  All
files recorded at the same time have the same version
numbers. 

The version numbers of files for playback can be selected at
the group or track level. By setting the group version
number to 5, you can play back the fifth take of a song, or
perhaps the fifth song of a live recording session. 

The track version setting, if present, overrides 
the group setting. Setting the track version to zero
restores control of the version number to the 
group setting.

=head2 REC/MON/OFF

Track REC/MON/OFF status guides audio processing.

Each track, including Master and Mixdown, has its own
REC/MON/OFF setting and displays its own REC/MON/OFF status.
The Main group, which includes all user tracks, also has
REC, MON and OFF settings that influence the behavior of all
user tracks.

As the name suggests, I<REC> status indicates that a track
is ready to record a WAV file. You need to set both track and
group to REC to source an audio stream from JACK or the
soundcard. 

I<MON> status indicates an audio stream available from disk.
It requires a MON setting for the track or group as well as
the presence of a file with the selected version number.  A
track set to REC with no live input will default to MON
status.

I<OFF> status means that no audio is available for the track
from any source. A track with no recorded WAV files 
will show OFF status, even if set to MON.

An OFF setting for a track or group always results in OFF
status, causing the track to be excluded from the
chain setup. I<Note: This setting is distinct from the action of
the C<mute> command, which sets the volume of the track to
zero.>

Newly created user tracks belong to the Main group, which
goes through a mixer and Master fader track to the 
soundcard for monitoring.

=head2 REGIONS

The C<region> command allows you to define endpoints
for a portion of an audio file. Use the C<shift> command
to specify a delay for starting playback.

Only one region may be specified per track.  Use the
C<link_track> command to clone a track in order to make use
of multiple regions or versions of a single track. 

C<link_track> can clone tracks from other projects.  Thus
you could create the sections of a song in separate
projects, pull them into one project using C<link_track> 
commands, and sequence them using C<shift> commands.

=head2 EFFECTS

Each track gets volume and pan effects by default.  New
effects added using C<add_effect> are applied after pan and
before volume.  You can position effects anywhere you choose
using C<insert_effect> and C<append_effect>.

=head3 SENDS AND INSERTS

The C<send> command can routes a track's post-fader output
to a soundcard channel or JACK client in addition to the
normal mixer input. Nama currently allows one aux send per
track.

The C<add_insert_cooked> command configures a post-fader
send-and-return to soundcard channels or JACK clients.
Wet and dry signal paths are provided, with a default
setting of 100% wet.

=head1 GROUPS

Track groups are used internally.  The Main group
corresponds to a mixer. It has its own REC/MON/OFF setting
that influences the rec-status of individual tracks. 

Setting a group to OFF forces all of the group's tracks to
OFF. When the group is set to MON, track REC settings are
forced to MON.  When the group is set to REC, track status
can be REC, MON or OFF. 

The group MON mode triggers automatically after a successful
recording run.

The B<mixplay> command sets the Mixdown track to MON and the
Main group to OFF.

=head2 BUNCHES

A bunch is just a list of track names. Bunch names are used
with the keyword C<for> to apply one or more commands to to several
tracks at once. A group name can also be treated as a bunch
name.

=head2 BUSES

Nama uses buses internally, and provides two kinds of
user-defined buses. 

B<Send buses> can be used as instrument monitors,
or to send pre- or post-fader signals from multiple
user tracks to an external program such as jconv.

B<Sub buses> (currently broken) enable multiple tracks to be
routed through a single track for vol/pan/effects processing
before reaching the mixer.

	add_sub_bus Strings
	add_tracks violin cello bass
	for violin cello bass; set bus Strings
	Strings vol - 10  # adjust bus output volume

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

=head4 B<testq> - Test

=over 8

C<testq> 

=back

=head2 Help commands

=head4 B<help> (h) - Display help

=over 8

C<help> [ <i_help_topic_index> | <s_help_topic_name> | <s_command_name> ]

=back

=head4 B<help_effect> (hfx he) - Display analyseplugin output if available or one-line help

=over 8

C<help_effect> <s_label> | <i_unique_id>

=back

=head4 B<find_effect> (ffx fe) - Display one-line help for effects matching search strings

=over 8

C<find_effect> <s_keyword1> [ <s_keyword2>... ]

=back

=head2 General commands

=head4 B<exit> (quit q) - Exit program, saving settings

=over 8

C<exit> 

=back

=head4 B<memoize> - Enable WAV dir cache

=over 8

C<memoize> 

=back

=head4 B<unmemoize> - Disable WAV dir cache

=over 8

C<unmemoize> 

=back

=head2 Transport commands

=head4 B<stop> (s) - Stop transport

=over 8

C<stop> 

=back

=head4 B<start> (t) - Start transport

=over 8

C<start> 

=back

=head4 B<getpos> (gp) - Get current playhead position (seconds)

=over 8

C<getpos> 

=back

=head4 B<setpos> (sp) - Set current playhead position

=over 8

C<setpos> <f_position_seconds>

C<setpos 65 (set play position to 65 seconds from start)>



=back

=head4 B<forward> (fw) - Move playback position forward

=over 8

C<forward> <f_increment_seconds>

=back

=head4 B<rewind> (rw) - Move transport position backward

=over 8

C<rewind> <f_increment_seconds>

=back

=head4 B<to_start> (beg) - Set playback head to start

=over 8

C<to_start> 

=back

=head4 B<to_end> (end) - Set playback head to end minus 10 seconds

=over 8

C<to_end> 

=back

=head4 B<ecasound_start> (T) - Ecasound-only start

=over 8

C<ecasound_start> 

=back

=head4 B<ecasound_stop> (S) - Ecasound-only stop

=over 8

C<ecasound_stop> 

=back

=head4 B<preview> - Start engine with rec_file disabled (for mic test, etc.)

=over 8

C<preview> 

=back

=head4 B<doodle> - Start engine while monitoring REC-enabled inputs

=over 8

C<doodle> 

=back

=head2 Mix commands

=head4 B<mixdown> (mxd) - Enable mixdown for subsequent engine runs

=over 8

C<mixdown> 

=back

=head4 B<mixplay> (mxp) - Enable mixdown file playback, setting user tracks to OFF

=over 8

C<mixplay> 

=back

=head4 B<mixoff> (mxo) - Set Mixdown track to OFF, user tracks to MON

=over 8

C<mixoff> 

=back

=head4 B<automix> - Normalize track vol levels, then mixdown

=over 8

C<automix> 

=back

=head4 B<master_on> (mr) - Enter mastering mode. Add tracks Eq, Low, Mid, High and Boost if necessary

=over 8

C<master_on> 

=back

=head4 B<master_off> (mro) - Leave mastering mode

=over 8

C<master_off> 

=back

=head2 General commands

=head4 B<main_off> - Turn off main output

=over 8

C<main_off> 

=back

=head4 B<main_on> - Turn on main output

=over 8

C<main_on> 

=back

=head2 Track commands

=head4 B<add_track> (add new) - Create a new track

=over 8

C<add_track> <s_name> [ <s_key1> <s_val1> <s_key2> <s_val2>... ]

C<add_track clarinet group woodwinds>



=back

=head4 B<add_tracks> (add new) - Create one or more new tracks

=over 8

C<add_tracks> <s_name1> [ <s_name2>... ]

C<add_track sax violin tuba>



=back

=head4 B<link_track> (link) - Create a read-only track that uses .WAV files from another track.

=over 8

C<link_track> <s_name> <s_target> [ <s_project> ]

C<link_track intro Mixdown song_intro creates a track 'intro' using all .WAV versions from the Mixdown track of 'song_intro' project>



=back

=head4 B<import_audio> (import) - Import a sound file (wav, ogg, mp3, etc.) to the current track, resampling if necessary.

=over 8

C<import_audio> <s_wav_file_path> [i_frequency]

=back

=head4 B<set_track> (set) - Directly set current track parameters (use with care!)

=over 8

C<set_track> <s_track_field> value

=back

=head4 B<rec> - REC-enable current track

=over 8

C<rec> 

=back

=head4 B<mon> - Set current track to MON

=over 8

C<mon> 

=back

=head4 B<off> (z) - Set current track to OFF (exclude from chain setup)

=over 8

C<off> 

=back

=head4 B<rec_defeat> (rd) - Toggle rec-defeat

=over 8

C<rec_defeat> 

=back

=head4 B<source> (src r) - Set track source

=over 8

C<source> <i_soundcard_channel> | <s_jack_client_name> | 'jack' (opens ports ecasound:trackname_in_N, connects ports listed in trackname.ports if present in project_root dir)

=back

=head4 B<send> (out aux m) - Set aux send

=over 8

C<send> <i_soundcard_channel> (3 or above) | <s_jack_client_name>

=back

=head4 B<remove_send> (nosend rms) - Remove aux send

=over 8

C<remove_send> none  what: set auxilary track destination

=back

=head4 B<stereo> - Record two channels for current track

=over 8

C<stereo> 

=back

=head4 B<mono> - Record one channel for current track

=over 8

C<mono> 

=back

=head4 B<set_version> (version n ver) - Set track version number for monitoring (overrides group version setting)

=over 8

C<set_version> <i_version_number>

C<sax; version 5; sh>



=back

=head4 B<destroy_current_wav> - Unlink current track's selected WAV version (use with care!)

=over 8

C<destroy_current_wav> 

=back

=head4 B<list_versions> (lver lv) - List version numbers of current track

=over 8

C<list_versions> 

=back

=head4 B<vol> (v) - Set, modify or show current track volume

=over 8

C<vol> [ [ + | - | * | / ] <f_value> ]

C<vol * 1.5 (multiply current volume setting by 1.5)>



=back

=head4 B<mute> (c cut) - Mute current track volume

=over 8

C<mute> 

=back

=head4 B<unmute> (C uncut) - Restore previous volume level

=over 8

C<unmute> 

=back

=head4 B<unity> - Set current track volume to unity

=over 8

C<unity> 

=back

=head4 B<solo> - Mute all but current track

=over 8

C<solo> 

=back

=head4 B<all> (nosolo) - Unmute tracks after solo

=over 8

C<all> 

=back

=head4 B<pan> (p) - Get/set current track pan position

=over 8

C<pan> [ <f_value> ]

=back

=head4 B<pan_right> (pr) - Pan current track fully right

=over 8

C<pan_right> 

=back

=head4 B<pan_left> (pl) - Pan current track fully left

=over 8

C<pan_left> 

=back

=head4 B<pan_center> (pc) - Set pan center

=over 8

C<pan_center> 

=back

=head4 B<pan_back> (pb) - Restore current track pan setting prior to pan_left, pan_right or pan_center

=over 8

C<pan_back> 

=back

=head4 B<show_tracks> (show tracks list_tracks lt) - Show status of all tracks

=over 8

C<show_tracks> 

=back

=head4 B<show_track> (sh) - Show current track status

=over 8

C<show_track> 

=back

=head4 B<set_region> (srg) - Specify a playback region for the current track using marks. Use 'new_region' for multiple regions.

=over 8

C<set_region> <s_start_mark_name> <s_end_mark_name>

=back

=head4 B<new_region> (nrg) - Create a region for the current track using an auxiliary track

=over 8

C<new_region> <s_start_mark_name> <s_end_mark_name> [<s_region_name>]

=back

=head4 B<remove_region> (rrg) - Remove region (including associated auxiliary track)

=over 8

C<remove_region> 

=back

=head4 B<shift_track> (shift) - Set playback delay for track or region

=over 8

C<shift_track> <s_start_mark_name> | <i_start_mark_index | <f_start_seconds>

=back

=head4 B<unshift_track> (unshift) - Remove playback delay for track or region

=over 8

C<unshift_track> 

=back

=head4 B<modifiers> (mods mod) - Set/show modifiers for current track (man ecasound for details)

=over 8

C<modifiers> [ Audio file sequencing parameters ]

C<modifiers select 5 15.2>



=back

=head4 B<nomodifiers> (nomods nomod) - Remove modifiers from current track

=over 8

C<nomodifiers> 

=back

=head4 B<normalize> (norm ecanormalize) - Apply ecanormalize to current track version

=over 8

C<normalize> 

=back

=head4 B<fixdc> (ecafixdc) - Apply ecafixdc to current track version

=over 8

C<fixdc> 

=back

=head4 B<autofix_tracks> (autofix) - Fixdc and normalize selected versions of all MON tracks

=over 8

C<autofix_tracks> 

=back

=head4 B<remove_track> - Remove effects, parameters and GUI for current track

=over 8

C<remove_track> 

=back

=head4 B<cache_track> (cache ct) - Record the post-fader signal as a new version

=over 8

C<cache_track> 

=back

=head2 Group commands

=head4 B<group_rec> (grec R) - Rec-enable user tracks

=over 8

C<group_rec> 

=back

=head4 B<group_mon> (gmon M) - Rec-disable user tracks

=over 8

C<group_mon> 

=back

=head4 B<group_version> (gn gver gv) - Set group version for monitoring (overridden by track-version settings)

=over 8

C<group_version> 

=back

=head4 B<group_off> (goff Z) - Group OFF mode, exclude all user tracks from chain setup

=over 8

C<group_off> 

=back

=head4 B<new_bunch> (nb) - Define a bunch of tracks

=over 8

C<new_bunch> <s_group_name> [<s_track1> <s_track2>...]

=back

=head4 B<list_bunches> (lb) - List track bunches

=over 8

C<list_bunches> 

=back

=head4 B<remove_bunches> (rb) - Remove the definition of a track bunch

=over 8

C<remove_bunches> <s_bunch_name> [<s_bunch_name>...]

=back

=head4 B<add_to_bunch> (ab) - Add track(s) to a bunch

=over 8

C<add_to_bunch> <s_bunch_name> <s_track1> [<s_track2>...]

=back

=head2 Project commands

=head4 B<save_state> (keep save) - Save project settings to disk

=over 8

C<save_state> [ <s_settings_file> ]

=back

=head4 B<get_state> (recall restore retrieve) - Retrieve project settings

=over 8

C<get_state> [ <s_settings_file> ]

=back

=head4 B<list_projects> (lp) - List projects

=over 8

C<list_projects> 

=back

=head4 B<create_project> (create) - Create a new project

=over 8

C<create_project> <s_new_project_name>

=back

=head4 B<load_project> (load) - Load an existing project using last saved state

=over 8

C<load_project> <s_project_name>

=back

=head4 B<project_name> (project name) - Show current project name

=over 8

C<project_name> 

=back

=head2 Setup commands

=head4 B<generate> (gen) - Generate chain setup for audio processing

=over 8

C<generate> 

=back

=head4 B<arm> - Generate and connect chain setup

=over 8

C<arm> 

=back

=head4 B<connect> (con) - Connect chain setup

=over 8

C<connect> 

=back

=head4 B<disconnect> (dcon) - Disconnect chain setup

=over 8

C<disconnect> 

=back

=head4 B<show_chain_setup> (chains) - Show current Ecasound chain setup

=over 8

C<show_chain_setup> 

=back

=head4 B<loop_enable> (loop) - Loop playback between two points

=over 8

C<loop_enable> <start> <end> (start, end: mark names, mark indices, decimal seconds)

C<loop_enable 1.5 10.0 (loop between 1.5 and 10.0 seconds) >

C<loop_enable 1 5 (loop between mark indices 1 and 5) >

C<loop_enable start end (loop between mark ids 'start' and 'end')>



=back

=head4 B<loop_disable> (noloop nl) - Disable automatic looping

=over 8

C<loop_disable> 

=back

=head2 Effect commands

=head4 B<add_controller> (acl) - Add a controller to an operator (use mfx to modify, rfx to remove)

=over 8

C<add_controller> <s_parent_id> <s_effect_code> [ <f_param1> <f_param2>...]

=back

=head4 B<add_effect> (afx) - Add effect to current track (placed before volume control)

=over 8

C<add_effect> <s_effect_code> [ <f_param1> <f_param2>... ]

C<add_effect amp 6 (LADSPA Simple amp 6dB gain)>

C<add_effect var_dali (preset var_dali) Note: no el: or pn: prefix is required>



=back

=head4 B<append_effect> - Add effect to the end of current track (mainly legacy use)

=over 8

C<append_effect> <s_effect_code> [ <f_param1> <f_param2>... ]

=back

=head4 B<insert_effect> (ifx) - Place effect before specified effect (engine stopped, prior to arm only)

=over 8

C<insert_effect> <s_insert_point_id> <s_effect_code> [ <f_param1> <f_param2>... ]

=back

=head4 B<modify_effect> (mfx modify_controller mcl) - Modify an effect parameter

=over 8

C<modify_effect> <s_effect_id> <i_parameter> [ + | - | * | / ] <f_value>

C<modify_effect V 1 -1 (set effect_id V, parameter 1 to -1)>

C<modify_effect V 1 - 10 (reduce effect_id V, parameter 1 by 10)>

C<set multiple effects/parameters: mfx V 1,2,3 + 0.5 ; mfx V,AC,AD 1,2 3.14>



=back

=head4 B<remove_effect> (rfx remove_controller rcl) - Remove effects from selected track

=over 8

C<remove_effect> <s_effect_id1> [ <s_effect_id2>...]

=back

=head4 B<add_insert_cooked> (ainc) - Add an external post-fader send/return to a track

=over 8

C<add_insert_cooked> <s_send_id> [<s_return_id>]

=back

=head4 B<set_insert_wetness> (wet) - Set wet/dry balance for track insert: 100 = all wet, 0 = all dry

=over 8

C<set_insert_wetness> <n_wetness>

=back

=head4 B<remove_insert> (rin) - Remove a track's insert

=over 8

C<remove_insert> 

=back

=head4 B<ctrl_register> (crg) - List Ecasound controllers

=over 8

C<ctrl_register> 

=back

=head4 B<preset_register> (prg) - List Ecasound presets

=over 8

C<preset_register> 

=back

=head4 B<ladspa_register> (lrg) - List LADSPA plugins

=over 8

C<ladspa_register> 

=back

=head2 Mark commands

=head4 B<list_marks> (lmk lm) - List all marks

=over 8

C<list_marks> 

=back

=head4 B<to_mark> (tmk tom) - Move playhead to named mark or mark index

=over 8

C<to_mark> <s_mark_id> | <i_mark_index>

C<to_mark start (go to mark named 'start')>



=back

=head4 B<new_mark> (mark k) - Drop mark at current playback position

=over 8

C<new_mark> [ <s_mark_id> ]

=back

=head4 B<remove_mark> (rmk rom) - Remove mark, default to current mark

=over 8

C<remove_mark> [ <s_mark_id> | <i_mark_index> ]

C<remove_mark start (remove mark named 'start')>



=back

=head4 B<next_mark> (nmk nm) - Move playback head to next mark

=over 8

C<next_mark> 

=back

=head4 B<previous_mark> (pmk pm) - Move playback head to previous mark

=over 8

C<previous_mark> 

=back

=head4 B<name_mark> (nmk nom) - Give a name to the current mark

=over 8

C<name_mark> <s_mark_id>

C<name_mark start>



=back

=head4 B<modify_mark> (move_mark mmk mm) - Change the time setting of current mark

=over 8

C<modify_mark> [ + | - ] <f_seconds>

=back

=head2 Diagnostics commands

=head4 B<engine_status> (egs) - Display Ecasound audio processing engine status

=over 8

C<engine_status> 

=back

=head4 B<dump_track> (dumpt dump) - Dump current track data

=over 8

C<dump_track> 

=back

=head4 B<dump_group> (dumpgroup dumpg) - Dump group settings for user tracks

=over 8

C<dump_group> 

=back

=head4 B<dump_all> (dumpall dumpa) - Dump most internal state

=over 8

C<dump_all> 

=back

=head4 B<show_io> (showio) - Show chain inputs and outputs

=over 8

C<show_io> 

=back

=head2 Help commands

=head4 B<list_history> (lh) - List command history

=over 8

C<list_history> 

=back

=head2 Bus commands

=head4 B<add_send_bus_cooked> (asbc) - Add a send bus that copies all user tracks' processed signals

=over 8

C<add_send_bus_cooked> <s_name> <destination>

C<asbc jconv>



=back

=head4 B<add_send_bus_raw> (asbr) - Add a send bus that copies all user tracks' raw signals

=over 8

C<add_send_bus_raw> <s_name> <destination>

C<asbr The_new_bus jconv>



=back

=head4 B<add_sub_bus> (asub) - Add a sub bus (default destination: to mixer via eponymous track)

=over 8

C<add_sub_bus> <s_name> [destination: s_track_name|s_jack_client|n_soundcard channel]

C<asub Strings_bus >

C<asub Strings_bus some_jack_client>



=back

=head4 B<update_send_bus> (usb) - Include tracks added since send bus was created

=over 8

C<update_send_bus> <s_name>

C<usb Some_bus>



=back

=head4 B<remove_bus> - Remove a bus

=over 8

C<remove_bus> <s_bus_name>

=back

=head4 B<list_buses> (lbs) - List buses and their parameters TODO

=over 8

C<list_buses> 

=back

=head4 B<set_bus> (sbs) - Set bus parameters TODO

=over 8

C<set_bus> 

=back

=head2 Effect commands

=head4 B<new_effect_chain> (nec) - Define a reusable sequence of effects (effect chain) with current parameters

=over 8

C<new_effect_chain> <s_name> [<op1>, <op2>,...]

=back

=head4 B<add_effect_chain> (aec) - Add an effect chain to the current track

=over 8

C<add_effect_chain> <s_name>

=back

=head4 B<overwrite_effect_chain> (oec) - Add an effect chain overwriting current effects (which are pushed onto stack)

=over 8

C<overwrite_effect_chain> <s_name>

=back

=head4 B<delete_effect_chain> (dec) - Remove an effect chain definition from the list

=over 8

C<delete_effect_chain> <s_name>

=back

=head4 B<list_effect_chains> (lec) - List effect chains, matching any strings provided

=over 8

C<list_effect_chains> [<s_frag1> <s_frag2>... ]

=back

=head4 B<bypass_effects> (bypass bye) - Bypass track effects (pushing them onto stack) except vol/pan

=over 8

C<bypass_effects> 

=back

=head4 B<replace_effects> (replace rep) - Restore bypassed track effects

=over 8

C<replace_effects> 

=back

=head4 B<uncache_track> (uncache unc) - Set uncached track version, restoring effects (if current version is cached)

=over 8

C<uncache_track> 

=back

=head2 General commands

=head4 B<do_script> (do) - Execute Nama commands from a file in project_dir or project_root

=over 8

C<do_script> <s_filename>

=back

=head4 B<scan> - Re-read project's .wav directory

=over 8

C<scan> 

=back



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

No waveform or signal level displays are provided.  No
latency compensation across signal paths is provided at
present, although this feature is planned.

=head1 SECURITY CONCERNS

If you are using Nama with the NetECI interface (i.e. if
Audio::Ecasound is I<not> installed) you should block TCP
port 2868 if you computer is exposed to the Internet. 

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

The main module, Nama.pm, its sister modules are
concatenations of several source files. Patches against the
source files are preferred.

=head1 AUTHOR

Joel Roth, E<lt>joelz@pobox.comE<gt>
