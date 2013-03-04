# ---------------- User Customization ---------------

package Audio::Nama;
use Modern::Perl;

sub setup_user_customization {
	my $filename = $file->user_customization();
	return unless -r $filename;
	say "reading user customization file $filename";
	my %custom;
	unless (%custom = do $filename) {
		say "couldn't parse $filename: $@\n" if $@;
		return;
	}
	logpkg(__FILE__,__LINE__,'debug','customization :', sub{yaml_out(\%custom)});
	my $prompt;
	$prompt = gen_coderef('prompt', $custom{prompt}) if $custom{prompt};
	{ no warnings 'redefine';
		*prompt = $prompt if $prompt;
	}
	my @commands = keys %{ $custom{commands} };
	for my $cmd(@commands){
		my $coderef = gen_coderef($cmd,$custom{commands}{$cmd}) or next;
		$text->{user_command}->{$cmd} = $coderef;
	}
	$text->{user_alias}   = $custom{aliases};
	map{ my $longform = $custom{fxshortcuts}->{$_};
		 if(effect_index($longform))
			{
				$fx_cache->{partial_label_to_full}->{$_} = $longform
			}
		 else 
			{ throw("$longform: effect not found, cannot create shortcut") 
			}
 	} keys %{$custom{fxshortcuts}};
}

sub gen_coderef {
	my ($cmd,$code) = @_;
	my $coderef = eval "sub{ use feature ':5.10'; $code }";
	say("couldn't parse command $cmd: $@"), return if $@;
	$coderef
}
1;