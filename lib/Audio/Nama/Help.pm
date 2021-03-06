# -------------------- Help ----------------------

package Audio::Nama;
use Modern::Perl;

{
no warnings 'uninitialized';
sub helpline {
	my $cmd = shift;
	my $out = "Command: $cmd\n";
	$out .=  "Shortcuts: $text->{commands}->{$cmd}->{short}\n"
			if $text->{commands}->{$cmd}->{short};	
	$out .=  "Category: $text->{commands}->{$cmd}->{type}\n";
	my $what = munge_help($text->{commands}->{$cmd}->{what});
	$out .=  "Description: $what\n";
	$out .=  "Usage: $cmd "; 

	if ( $text->{commands}->{$cmd}->{parameters} 
			&& $text->{commands}->{$cmd}->{parameters} ne 'none' ){
		$out .=  $text->{commands}->{$cmd}->{parameters}
	}
	$out .= "\n";
	my $example = $text->{commands}->{$cmd}->{example};
	$example = munge_help($example);
	#$example =~ s/!n/\n/g;
	if ($example){
		$out .=  "Example: ";
		if ($example =~ /\n/s){
			$example = "\n$example";    # add leading newline
			$example =~ s(\n)(\n    )g; # indent
		}
		$out .=  $example;
		$out .= "\n";
	}
	($/, ucfirst $out, $/);
	
}
sub munge_help {
	my $text = shift;
	$text =~ s/(^\s*)!(\s*#)/$1 $2/mg;
	$text =~ s/(^\s*!)/#/mg;
	$text
}
}
sub helptopic {
	my $user_input = shift;

	# we expect topic number or topic name
	
	my ($index, $name);
	if( $user_input =~ /(\D+)/ ){ 
		$name = $1;
	}
	else { 
		$index = $user_input;
		$name = $help->{arr_topic}->[$index];
	}
	#system("man","nama") if $index== 15;
	format_help_topic($index, $name);
}

sub format_help_topic {
	my ($index, $name) = @_;
	my @output;
	push @output, "\n-- ", ucfirst $name, " --\n\n";
	push @output, $help->{topic}->{$name}, $/;
	push @output, $help->{usage} if $index == 14;
	@output
}

sub help { 
	my $name = shift;
	$name =~ s/-/_/g;  # help indices require underscores
	chomp $name;
	#print "seeking help for argument: $name\n";
	$text->{iam}->{$name} and pager(<<IAM);

$name is an Ecasound command.  See 'man ecasound-iam'.
IAM
	my @output;
	if ( $help->{topic}->{$name}){
		@output = helptopic($name);
	} elsif ($name =~ /^0/){
		@output = map{ helptopic $_ } @{$help->{arr_topic}};
	} elsif ( $name =~ /^(\d+)$/ and $1 < 20  ){
		@output = helptopic($name)
	} else {
		my %helped = (); 
		my @help = ();
		if ( $text->{commands}->{$name} ){
			push @help, helpline($name);
			$helped{$name}++
		}
		map
		{  
			my $cmd = $_ ;
			if ($cmd =~ /$name/ )
			{
				push @help, helpline($cmd) unless $helped{$cmd}
					or $cmd =~ /-/; # skip hyphenated command forms
									# which lack full help
				$helped{$cmd}++ ;
			}
			no warnings 'uninitialized';
			if ( ! $helped{$cmd} and
					grep{ /$name/ } split " ", $text->{commands}->{$cmd}->{short})
			{
				push @help, helpline($cmd) 
			}
		} keys %{$text->{commands}};

		if ( @help ){ push @output, 
			qq("$name" matches the following commands:\n\n), @help;
		}
	}
	if (@output){
		map{ s/_/-/g } @output;
		Audio::Nama::pager( @output ); 
	} else { throw("$name: no help found.\n"); }
	
}
sub help_effect {
	my ($input, $id, $no_match, @output);
	$id = $input = shift;
	push @output, "\n";

	# e.g. help tap_reverb    
	#      help 2142
	#      help var_chipmunk # preset

	# convert digits to LADSPA label

	if ($id !~ /\D/){ $id = $fx_cache->{ladspa_id_to_label}->{$id} or $no_match++ } 

	# convert ladspa_label to el:ladspa_label
	# convert preset_name  to pn:preset_name
	
	if ($fx_cache->{full_label_to_index}->{$id}){} # we are ready
	elsif ( $fx_cache->{partial_label_to_full}->{$id} ) { $id = $fx_cache->{partial_label_to_full}->{$id} }
	else { $no_match++ }

	# one-line help for Ecasound presets
	
	if ($id =~ /pn:/) {
		push @output, grep{ /$id/  } @{$fx_cache->{user_help}};
	}

	# full help for LADSPA/LV2 plugins
	
	elsif ( $id =~ /el:/  ) { @output = $fx_cache->{ladspa_help}->{$id} }
	elsif ( $id =~ /elv2:/) { @output = $fx_cache->{lv2_help}->{$id}    }
	else { 
		@output = qq("$id" is an Ecasound chain operator.
Type 'man ecasound' at a shell prompt for details.);
	}

	if( $no_match ){ throw("No effects were found matching: $input\n\n"); }
	else { Audio::Nama::pager(@output) }
}

sub find_effect {
	my @keys = @_;
	#print "keys: @keys\n";
	#my @output;
	my @matches = grep{ 
		my $_help = $_; 
		my $didnt_match;
		map{ $_help =~ /\Q$_\E/i or $didnt_match++ }  @keys;
		! $didnt_match; # select if no cases of non-matching
	} @{$fx_cache->{user_help}};
	if ( @matches ){
	Audio::Nama::pager( $text->{wrap}->paragraphs(@matches) , "\n" );
	} else { throw(join " ", "No effects were found matching:",@keys,"\n\n") }
}


@{$help->{arr_topic}} = qw( all
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

@{$help->{arr_topic}} = qw( all
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
					edits
					fades
					command_line_options
					man_page
                ) ;

%{$help->{topic}} = (

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
   project_name, name        - show the current project name
   create_project, create    - create a new project directory tree 
   list_projects, lp         - list all Nama projects
   get_state, get            - retrieve named file or tag
   save_state, keep, save    - save state as file or tag
   exit, quit                - exit program, saving state 

 (Version control)

   save                      - save, commit and tag with <tagname>
   get                       - checkout tag <tagname> 
                               or associated branch and load
   branch, br                - switch to designated branch and load
   list_branches, lbr        - list branches and tags (without arguments)
   new_branch, nbr           - create a new branch starting at the current 
                               commit or a specified commit 
   tag                       - tag current commit with a name and optional 
                               message
   
   memoize                   - enable WAV directory cache
   unmemoize                 - disable WAV directory cache
   
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

   rec                     -  set track to REC (live signal source)
   mon                     -  set track to PLAY (WAV file playback)
   off                     -  set track OFF (omit from setup)
   write_defeat, wd        -  toggle track WAV recording off
   write_enable, we        -  toggle track WAV recording on

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
   unmute, nomute, uncut, C -  restore muted volume

 - chain object modifiers

   mod, mods, modifiers    - show or assign select/reverse/playat modifiers
                             for current track
   nomod, nomods, 
   nomodifiers             - remove all modifiers from current track

 - signal processing

   ecanormalize, normalize, norm 
                           - run ecanormalize on current track version
   ecafixdc, fixdc         - run ecafixdc on current track version
   autofix_tracks, autofix - fixdc and normalize selected versions of all PLAY
                             tracks

 - cutting and time shifting

   set_region,    srg      - specify a track region using times or mark names
   add_region,    arg      - define a region creating an auxiliary track
   remove_region, rrg      - remove auxiliary track or region definition
   shift_track,   shift    - set playback delay for track/region
   unshift_track, unshift  - eliminate playback delay for track/region

- track caching (intermediate mixdown)

   cache_track,   cache,   ct  - store effects-processed track signal as new version
   uncache_track, uncache, unc - select uncached track version, replace effects

 - hazardous or destructive commands for advanced users

   set_track               - directly set current track parameters

   destroy_current_wav     - unlink current track's selected WAV version.

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
   modify_effect,  mfx        - set, increment or decrement effect parameter
   remove_effect,  rfx        - remove an effect or controller
   append_effect, apfx        - add effect to the end of current track effect list 
   bypass_effects, bypass, bye   - suspend current track effects except vol/pan
   restore_effects, restore, ref - restore track effects

-  send/receive inserts

   add_insert,         ain    - add an insert to current track
   remove_insert,      rin    - remove an insert from current track
   set_insert_wetness, wet    - set/query insert wetness 
                                example: wet 99 (99% wet, 1% dry)

-  effect chains (presets, each consisting of multiple effects)

   list_effect_chains,     lec   - list effect chains and their parameters
   new_effect_chain,       nec   - define a new effect chain
   overwrite_effect_chain, oec   - as above, but overwite existing definition
   add_effect_chain,       aec   - add an effect chain to the current track
   delete_effect_chain,    dec   - delete an effect chain definition

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
   group_mon, gmon, M         - group PLAY mode 
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
                            (operates on tracks in current bus w/status OFF)
GROUP

bus => <<BUS,
   list_buses,          lbs   - list bus data
   add_submix_raw,      asr   - create bus and slave tracks for 
                                sending pre-fader track signals
   add_submix_cooked, asc     - as above, for post-fader signals
   update_submix,     usm     - refresh send bus track list
   remove_bus,                - remove a bus
   add_bus,           abs     - create a sub-bus feeding a regular user track
                                of the same name
                                example: add_bus Strings 
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
# print values %{$help->{topic}};

$help->{screen} = <<HELP;

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
14 Command line options
15 Man page

HELP

1;