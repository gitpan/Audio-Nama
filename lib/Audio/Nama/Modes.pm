# ----------- Modes: mastering, preview, doodle ---------

package Audio::Nama;
use Modern::Perl;
{
sub set_preview_mode {

	# set preview mode, releasing doodle mode if necessary
	
	logsub("&preview");

	# do nothing if already in 'preview' mode
	
	return if $mode->preview;

	$mode->{preview} = "preview";

	pager( <<'MSG');
Setting preview mode.
Using both REC and PLAY inputs.
WAV recording is DISABLED.

Type 'arm' to enable recording.
MSG

}
sub set_doodle_mode {

	logsub("&doodle");
	return if engine_running() and Audio::Nama::ChainSetup::really_recording();
	$mode->{preview} = "doodle";

	$tn{Mixdown}->set(rw => OFF);
	
	# reconfigure_engine will generate setup and start transport
	
pager( <<'MSG' );
Setting doodle mode.
Using live inputs only, no duplicate inputs
Exit using 'preview' or 'arm' commands
MSG

}
sub exit_preview_mode { # exit preview and doodle modes

		logsub("&exit_preview_mode");
		return unless $mode->{preview};
		stop_transport() if engine_running();
		pager("Exiting preview/doodle mode");
		$mode->{preview} = 0;

}

sub master_on {

	return if $mode->mastering;
	
	# create mastering tracks if needed
	
	if ( ! $tn{Eq} ){  
	
		local $this_track;
		add_mastering_tracks();
		add_mastering_effects();
	} else { 
		unhide_mastering_tracks();
		map{ $ui->track_gui($tn{$_}->n) } @{$mastering->{track_names}};
	}

}
sub master_off {
	return if ! $mode->mastering;
	hide_mastering_tracks();
	map{ $ui->remove_track_gui($tn{$_}->n) 
		} @{$mastering->{track_names}};
	$this_track = $tn{Master} if grep{ $this_track->name eq $_} @{$mastering->{track_names}};
;
}

sub add_mastering_tracks {

	map{ 
		my $track = Audio::Nama::MasteringTrack->new(
			name => $_,
			rw => MON,
			group => 'Mastering', 
		);
		$ui->track_gui( $track->n );

 	} grep{ $_ ne 'Boost' } @{$mastering->{track_names}};
	my $track = Audio::Nama::BoostTrack->new(
		name => 'Boost', 
		rw => MON,
		group => 'Mastering', 
		target => 'Master',
	);
	$ui->track_gui( $track->n );

	
}


sub add_mastering_effects {
	
	$this_track = $tn{Eq};

	process_command("add_effect $mastering->{fx_eq}");

	$this_track = $tn{Low};

	process_command("add_effect $mastering->{fx_low_pass}");
	process_command("add_effect $mastering->{fx_compressor}");
	process_command("add_effect $mastering->{fx_spatialiser}");

	$this_track = $tn{Mid};

	process_command("add_effect $mastering->{fx_mid_pass}");
	process_command("add_effect $mastering->{fx_compressor}");
	process_command("add_effect $mastering->{fx_spatialiser}");

	$this_track = $tn{High};

	process_command("add_effect $mastering->{fx_high_pass}");
	process_command("add_effect $mastering->{fx_compressor}");
	process_command("add_effect $mastering->{fx_spatialiser}");

	$this_track = $tn{Boost};
	
	process_command("add_effect $mastering->{fx_limiter}"); # insert after vol
}

sub unhide_mastering_tracks {
	process_command("for Mastering; set_track hide 0 rw MON");
}

sub hide_mastering_tracks {
	process_command("for Mastering; set_track hide 1 rw OFF");
 }
}
		
1;
__END__