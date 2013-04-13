package Audio::Nama::Globals;
use Modern::Perl;

# set aliases for common indices
*bn = \%Audio::Nama::Bus::by_name;
*tn = \%Audio::Nama::Track::by_name;
*ti = \%Audio::Nama::Track::by_index;

# and the graph

*g = \$Audio::Nama::ChainSetup::g;

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
$g
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
@tracked_vars
@persistent_vars

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

						@tracked_vars
						@persistent_vars
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
$g
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
@tracked_vars
@persistent_vars


	)],
);
our $ui = 'bullwinkle';  # for testing
{
	my %seen;
	push @{$EXPORT_TAGS{all}}, grep {!$seen{$_}++} @{$EXPORT_TAGS{$_}} foreach
keys %EXPORT_TAGS;
}


1;