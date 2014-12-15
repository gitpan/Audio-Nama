# ----------- Logging ------------

package Audio::Nama::Log;
use Modern::Perl;
use Log::Log4perl qw(get_logger :levels);
use Exporter;
use Carp;
our @ISA = 'Exporter';
our @EXPORT_OK = qw(logit logsub initialize_logger);
our $appender;

sub initialize_logger {
	my $cat_string = shift;

	my @all_cats = qw(
CacheTrack
Engine_cleanup
Util
Config
Insert
IO
Engine_setup
Bunch
Custom
Track
Mode
Effects
Latency
Engine
Persistence
Fade
Terminal
Jack
Grammar
Effects_registry
Project
Mute
EffectChain
Mark
	);

	my %negate = map{ $_ => 1} map{ s/^!//; $_ } grep{ /^!/ } 
		expand_cats(split q(,), $cat_string);
	#say("negate\n",Audio::Nama::yaml_out(\%negate));

	my $layout = "[\%r] %c %m%n"; # backslash to protect from source filter
	my $logfile = $ENV{NAMA_LOGFILE} || "";
	$SIG{ __DIE__ } = sub { Carp::confess( @_ ) } if $cat_string;
	
	$appender = $logfile ? 'FILE' : 'STDERR';

	my @cats = expand_cats(split ',', $cat_string);
	#say "log cats: @cats";
	
	@cats = grep{ ! $negate{$_} } expand_cats(@all_cats) if grep {$_ eq 'ALL'} @cats;
	#say "Logging categories: @cats" if @cats;

	#say Dumper %log_cats;

	my $conf = qq(
		#log4perl.rootLogger			= DEBUG, $appender
		#log4perl.category.Audio.Nama	= DEBUG, $appender

		# dummy entry - avoid no logger/no appender warnings
		log4perl.category.DUMMY			= DEBUG, DUMMY
		log4perl.appender.DUMMY			= Log::Log4perl::Appender::Screen
		log4perl.appender.DUMMY.layout	= Log::Log4perl::Layout::NoopLayout

		# screen appender
		log4perl.appender.STDERR		= Log::Log4perl::Appender::Screen
		log4perl.appender.STDERR.layout	= Log::Log4perl::Layout::PatternLayout
		log4perl.appender.STDERR.layout.ConversionPattern = $layout

		# file appender
		log4perl.appender.FILE		= Log::Log4perl::Appender::File
		log4perl.appender.FILE.filename	= $logfile
		log4perl.appender.FILE.layout	= Log::Log3perl::Layout::PatternLayout
		log4perl.appender.FILE.layout.ConversionPattern = $layout

		#log4perl.additivity.SUB			= 0 # doesn't work... why?
	);
	# add lines for the categories we want to log
	$conf .= join "\n", "", map{ cat_line($_)} @cats if @cats;
	#say $conf; 
	Log::Log4perl::init(\$conf);
	return( { map { $_, 1 } @cats } )
}
sub cat_line { "log4perl.category.$_[0]			= DEBUG, $appender" }

sub expand_cats {
	my @cats = @_;
	map { s/^(!)?::/$1Audio::Nama::/; $_}                    # SKIP_PREPROC
	map { s/^(!)?/$1::/ unless /^::/ or /^!?ECI/ or /^!?SUB/ or /^ALL$/; $_ }# SKIP_PREPROC
	@cats;
}
{
my %is_method = map { $_ => 1 } 
		qw( trace debug info warn error fatal
			logwarn logdie
			logcarp logcroak logcluck logconfess);
	
sub logit {
	my ($line_number, $category, $level, @message) = @_;
	#say qq($line_number, $category, $level, @message) ;
	my $line_number_output  = $line_number ? " (L $line_number) ": "";
	return unless $category;
	confess "illegal level: $level" unless $is_method{$level};
	my $logger = get_logger($category);
	$logger->$level($line_number_output, @message);
}
}
sub logsub { logit(__LINE__,'SUB','debug',$_[0]) }
	
1;