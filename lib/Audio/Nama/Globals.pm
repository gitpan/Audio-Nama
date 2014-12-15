package Audio::Nama::Globals;
use Modern::Perl;
*bn = \%Audio::Nama::Bus::by_name;
*tn = \%Audio::Nama::Track::by_name;
*ti = \%Audio::Nama::Track::by_index;
use Exporter;
our @ISA = 'Exporter';
our @EXPORT_OK = qw(

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
@config_vars
@persistent_vars
@new_persistent_vars
@project_config_vars

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

	pronouns => [qw(
						$this_track
						$this_bus
						$this_op
						$this_param
						$this_mark
						$this_edit
						%tn
						%ti
						%bn
						$prompt
	)],

	var_types => [qw(

						@config_vars
						@persistent_vars
						@new_persistent_vars
						@global_effect_chain_vars
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


	)],
);
our $ui = 'bullwinkle';  # for testing
{
	my %seen;
	push @{$EXPORT_TAGS{all}}, grep {!$seen{$_}++} @{$EXPORT_TAGS{$_}} foreach
keys %EXPORT_TAGS;
}


1;