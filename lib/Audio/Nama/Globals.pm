package Audio::Nama::Globals;
use Modern::Perl;

# set aliases for common indices
*bn = \%Audio::Nama::Bus::by_name;
*tn = \%Audio::Nama::Track::by_name;
*ti = \%Audio::Nama::Track::by_index;

use Exporter;
our @ISA = 'Exporter';
our @EXPORT_OK = qw(

$this_track
$this_bus
$this_op
$this_param
$this_mark
$this_edit
$prompt
%tn
%ti
%bn
$debug
$debug2
$ui
$mode
$file
$graph
$setup
$config
$jack
$fx
$fx_cache
$engine
$text
$gui
$midi
$help
$mastering
$project
@tracks_data
@bus_data
@groups_data
@marks_data
@fade_data
@edit_data
@inserts_data
@global_effect_chain_vars
@global_effect_chain_data
@project_effect_chain_data
$this_track_name
%track_comments
%track_version_comments
@persistent_vars
@persistent_untracked_vars

);

our %EXPORT_TAGS = 
(
	singletons => [qw( 	

$ui
$mode
$file
$graph
$setup
$config
$jack
$fx
$fx_cache
$engine
$text
$gui
$midi
$help
$mastering
$project


	)],

	var_lists => [qw(

						@persistent_vars
						@persistent_untracked_vars
						@global_effect_chain_vars
	)],

	pronouns => [qw( 

$this_track
$this_bus
$this_op
$this_param
$this_mark
$this_edit
$prompt
%tn
%ti
%bn
$debug
$debug2


	)],

	serialize =>  [qw(

@tracks_data
@bus_data
@groups_data
@marks_data
@fade_data
@edit_data
@inserts_data
@global_effect_chain_vars
@global_effect_chain_data
@project_effect_chain_data
$this_track_name






%track_comments
%track_version_comments
@persistent_vars
@persistent_untracked_vars


	)],
);
our $ui = 'bullwinkle';  # for testing
{
	my %seen;
	push @{$EXPORT_TAGS{all}}, grep {!$seen{$_}++} @{$EXPORT_TAGS{$_}} foreach
keys %EXPORT_TAGS;
}


1;