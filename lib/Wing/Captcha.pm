package Wing::Captcha;

use Wing;
use Wing::Perl;
use String::Random qw(random_string);
use Ouch;
use Wing::Util qw(random_element);

sub get {
	my $riddle = choose_riddle(); 
	my $key = generate_key();
	Wing->cache->set('captcha_'.$key, $riddle->[1], 60 * 15);
	return {
		key 			=> $key, 
		riddle 			=> to_entities($riddle->[0]),
	};
}

sub verify {
	my ($key, $user_answer) = @_;
	my $correct_answer = Wing->cache->get('captcha_'.$key);
	if ($correct_answer eq '') {
		ouch 412, 'Captcha expired';
	}
	unless ($user_answer eq $correct_answer) {
		ouch 412, 'Captcha failed';
	}
	return 1;
}

sub generate_key {
	return random_string('ssssssssssssssssssss');
}

sub choose_riddle {
	my $riddles = build_riddles();
	my $key    = random_element([ keys %{$riddles} ]);
        my $value  = $riddles->{$key};
    	return [ $key, $riddles->{$key} ];
}

sub build_riddles {

	my %riddles = (
	    "1x1x1=_"     => "1",
	    "0x0x0=_"     => "0",
	    "0+0+0=_"     => "0",
	    "0-0-0=_"     => "0",
	    "1/1=_"       => "1",
	    "2/1=_"       => "2",
	    "2/2=_"       => "1",
	    "4/2=_"       => "2",
	    "6/2=_"       => "3",
	    "6/3=_"       => "2",
	    "9/3=_"       => "3",
	    "10/2=_"      => "5",
	    "10/5=_"      => "2",
	    "12/3=_"      => "4",
	    "12/4=_"      => "3",
	);

	# 5+5=_
	# 5-5=_
	# 5x5=_
	for my $a (1..9) {
	    for my $b (1..9) {
		$riddles{$a.'+'.$b.'=_'} = $a + $b;
		$riddles{$a.'-'.$b.'=_'} = $a - $b;
		$riddles{$a.'x'.$b.'=_'} = $a * $b;
	    }
	}

	# 1,2_4,5
	for my $a ('1'..'2') {
	    for (1..2) {
		my $string = $a++;
		$string .= ',';
		$string .= $a++;
		my $answer = $a++;
		$answer .= ',';
		$answer .= $a++;
		$string .= ',_,';
		$string .= $a++;
		$string .= ',';
		$string .= $a++;
		$riddles{$string} = $answer;
	    }
	}

	# abc_ghi
	for my $a ('a'..'i') {
	    for (1..2) {
		my $string = $a++;
		$string .= $a++;
		$string .= $a++;
		my $answer = $a++;
		$answer .= $a++;
		$answer .= $a++;
		$string .= '_';
		$string .= $a++;
		$string .= $a++;
		$string .= $a++;
		$riddles{$string} = $answer;
	    }
	}

	return \%riddles;
}

sub to_entities {
	my $string = shift;
	my $out = '';
	foreach my $character (split(//, $string)) {
		$out .= '&#'.ord($character).';';
	}
	return $out;
}



1;
