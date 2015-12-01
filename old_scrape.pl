use warnings;
use strict;

use HTML::Tree;
use HTML::TreeBuilder;

use Data::Dumper;

use DBI;

my $url = 'http://www.houstontx.gov/citysec/agenda/agendaindex.html';
my $db = DBI->connect("dbi:SQLite:dbname=open", "", "");

print "Downloading main file\n";
system("curl $url > agendaindex.html");

my $tree = HTML::TreeBuilder->new_from_file('agendaindex.html');

my $table = $tree->look_down("width" => "90%");
my @links = $table->look_down(_tag => 'a');

my @pdfs;

print "Getting pdf links\n";
foreach my $link (@links) {
	if ($link->attr('href') =~ /pdf/g) {
		my $pdfLink = 'http://www.houstontx.gov/citysec/agenda/' . $link->attr('href');
		push(@pdfs, $pdfLink);
	}
}

print "Found ", scalar @pdfs, " pdf links\n";

my $pdfCount = 0;
foreach (@pdfs) {
	$pdfCount++;
	print "On pdf $pdfCount out of ", scalar @pdfs, "\n";
	my $url = $_;
	print "Downloading pdf: $_ \n";
	system("curl $_ > pdf_temp.pdf");
	print "Converting to txt\n";
	system("pdf2txt.py -o output.txt pdf_temp.pdf");
	
	open(my $fh, "output.txt");
	my @lines =  <$fh>;
	close($fh);

	print "Stripping white space\n";
	system('perl -i.bak -ne "print if /\S/" output.txt');
	
	my @dateParts = split(/ - /, $lines[0]);
	my $date = $dateParts[3];

	print "Looping through lines\n";
	
	for (my $i = 0; $i < scalar @lines; $i++) {
		$lines[$i] =~ s/\n//;
		$lines[$i] =~ s/^\s+//;
		if ( ($lines[$i] =~ /NUMBER/g) || ($lines[$i] =~ /^HEARINGS/g) ) { #found a description
			my @descripParts = split(/ - /, $lines[$i]);
			my $description = $descripParts[0];
			print "Found a description : $description at line $i on line $lines[$i] \n";
		
			#looping until found another description
	
			$i++;	

			my @motions;
	
			print "Looping until finding another description\n";	
			until ($lines[$i] =~ /([A-Z]|\s)+/g && $lines[$i] =~ /NUMBER/ or $i >= scalar @lines) {
				my $motionString = "";
				#print "$i \n";
				if ($lines[$i] =~ /^\d+[.]/) { #found a motion
#					print "Found a motion at line $i at line $lines[$i] \n";
					$motionString = $lines[$i];
#					$motionString =~ s/^\d+[.]\s//;
					$i++;
					until ($lines[$i] =~ /^\d+[.]/ or !(defined($lines[$i]))) {
						$motionString = $motionString . $lines[$i];	
						$i++;
					}
#					print "Found motion: $motionString \n";
					push(@motions, $motionString);
				}
				$i++;
			}

			foreach (@motions) {
				s/ +/ /;
				s/\n/ /;
				s/\t/ /;
				s/\s/ /;
				$description =~ s/\s/ /;
				my $st = $db->prepare("INSERT INTO old VALUES(?, ?, ?, ?);");
				$st->execute($url, $_, $_, $description);
			}
			
			print "found ", scalar @motions, " motions \n";		
		}
	}
}

