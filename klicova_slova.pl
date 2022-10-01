#!/usr/bin/perl
use strict;
use warnings;

use utf8;
use open qw/:std :utf8/;
use Text::CSV_XS::TSV;
use List::Util qw (sum first min);
use Getopt::Long;

my $simplePrint = 0;
my $help = 0;
my $language = 'cze';
my ($input, $output);
my ($ifh, $ofh);

my $version = '1.0';
my $repo_url = 'https://github.com/Tadeas-Jun/czech-keywords';

if (!@ARGV) {
    $help = 1;
}

GetOptions(
    "simplePrint"   => \$simplePrint,
    "help|?|man"    => \$help,
    "input=s"       => \$input,
    "output=s"      => \$output,
    "language=s"    => \$language
);

my $help_text = <<EOF;

klicova_slova.pl je program pro extrahování klíčových slov z českého dokumentu. Používáte verzi programu $version.

Pro extrahování slov spusťte program s parametrem --input (a --output). Dobrovolně můžete přidat i parametr --simplePrint, který
způsobí pouze vypsání samotných klíčových slov; jinak program vypíše i informace o procesu analýzy textu.

Příklad spuštění:
    perl klicova_slova.pl --input inputText.txt --output keywords.txt --simplePrint --language eng

Spusťte program bez parametru nebo s parametrem --help pro zobrazení této zprávy.

Spusťte program s parametrem --language pro přepínání jazyka výpisových informací mezi češtinou a angličtinou. Parametr může mít hodnoty 'cze' nebo 'eng'.
Bez přidání parametru se automaticky zvolí čeština. Tato nápověda a zprávy s errory se vždy zobrazí v obou jazycích.

Autorem projektu je Tadeáš Jůn. Zdrojový kód, dodatečné informace o programu, uživatelská dokumentace, a možnosti podpory projektu
jsou dostupné v projektovém repozitáři:
    $repo_url

-------------------------

klicova_slova.pl is a program used for keyword extraction from Czech documents. You are using version $version of the project.

To extract keywords, run the code with the --input (and --ouput) parameters. Optionally, you can add the --simplePrint parameter to
only output the keywords themselves; otherwise, the program prints out additional information about the text analysis process.

Example command:
    perl klicova_slova.pl --input inputText.txt --output keywords.txt --simplePrint --language eng

Run the program without any parameters or with the --help parameter to view this message.

Run the program with the --language parametr to switch the information ouput language between Czech and English. The parametr can have values
of 'cze' or 'eng'. If no value is specified, the program defaults to Czech. This help message and the error messages will always be displayed
in both languages.

The author of this project is Tadeas Jun. You can find the source code, additional info about the code, the user documentation,
and ways to support the project in the project repository:
    $repo_url

EOF

# Print help message if no parameters or --help parameter specified.
if ($help) {
    print($help_text);
    exit 0;
}

if ($input) {
    open $ifh, "<", $input or die "Zadaný --input soubor nebyl nalezen či se ho nepovedlo otevřít.\nI could not find or open the --input file.\n";
} elsif (!$help) {
    print STDERR "Pro extrahování slov spusťte program s parametry --input (a --output).\nTo extract keywords, run the code with the --input (and --ouput) parameters.\n";
    exit 0;
}

if ($output) {
    open $ofh, ">", $output or die "Zadaný --output soubor se nepovedlo otevřít či vytvořit.\nI could not open or create the --output file.\n";
    *STDOUT = $ofh;
}

if ($language && !grep(/^${language}$/, qw(cze eng))) {
    print STDERR "Definovaný jazyk (--language) musí být 'cze' nebo 'eng'.\nThe defined --language has to be 'cze' or 'eng'.\n";
    exit 0;
}

# Load all words from the input.
sub GetAllWords {

    my $data = "";
    while (<$ifh>) {
        my $line = $_;
        chomp $line;
        $data .= $line;
    }

    my @words = ();
    while ($data =~ /(\S+)/g) {

        my $word = $1;

        # Remove punctuation and other symbols from word.
        $word =~ tr/.,!?;:"'()–[]{}|0123456789//d;

        # Convert word to lower case.
        $word = lc $word;

        push(@words, $word);

    }

    return @words;

}

# Load the Czech Corpus.
sub GetCzechCorpus {

    my $corpus = Text::CSV_XS::TSV->new({ binary => 1, auto_diag => 1 });

    my $corpusFile = "corpus/syn2015_word_utf8.tsv";
    open my $in, "<", $corpusFile or die "Can't open file $corpusFile: $!";

    my @corpusWords;
    while (my $row = $corpus->getline($in)) {

        my $word;
        $word = {
            rank      => @$row[0],
            word      => lc @$row[1],
            frequency => @$row[2]
        };

        push(@corpusWords, $word);

    }

    close $in or die $!;

    return @corpusWords;

}

# Remove all defined stop words (common words that usually don't hold any meaning).
sub RemoveStopWords {

    my @wordList = @{ $_[0] };
    my @frequentCorpusWords = @{ $_[1] };

    # Remove all elements that appear in @frequentCorpusWords from @worldList.
    @wordList = grep { my $w = $_; !grep %$_{word} eq $w, @frequentCorpusWords } @wordList;

    return @wordList;

}

# Removes all words with 3 or less characters - those usually don't hold any meaning.
sub RemoveShortWords {

    my @wordList = @{ $_[0] };

    @wordList = grep { length($_) > 3 } @wordList;

    return @wordList;

}

# Count the frequencies of all given words in the text.
sub GetWordFrequencies {

    my @wordList = @{ $_[0] };

    my %count;
    foreach my $word (@wordList) {
        $count{$word}++;
    }

    return %count;

}

# Removes all words that are below the frequency threshold (see documentation for explanation).
sub RemoveUnusualWords {

    my %frequencies = %{ $_[0] };
    my $totalWordCount = $_[1];

    # Calculate the threshold.
    my $cutoffPointFrequency = int((log($totalWordCount) / log(10)) + 0.5);

    if (!$simplePrint) {
        print($language eq 'cze' ? "Odstřanuji slova s frekvencí méně než $cutoffPointFrequency: " : "Cutting off words with an occurance less than $cutoffPointFrequency: ");
    }

    foreach (keys %frequencies) {

        if ($frequencies{$_} < $cutoffPointFrequency) {
            delete $frequencies{$_};
        }

    }

    return %frequencies;

}

# Calculate an importance value for each given word according to the importance formula (see documentation).
sub CalculateImportanceValues {

    my %frequencies = %{ $_[0] };
    my @corpusWords = @{ $_[1] };

    my %importances;

    if (!$simplePrint) {
        print($language eq 'cze' ? "Počítám důležitost až " . %frequencies . " slov. Tento proces může zabrat až pár minut...\n\n" : "Assigning an importance value to up to " . %frequencies . " words. This might take a while...\n\n");
    }

    my $totalFrequency = sum values %frequencies;

    foreach my $word (keys %frequencies) {

        my @frequenciesInCorpus = first { $word eq $_->{word} } @corpusWords;
        my $frequencyInCorpus = $frequenciesInCorpus[0]{frequency};

        # Skip every word that's not in the corpus.
        if (!$frequencyInCorpus) {
            next;
        }

        # Calculate the importance (see documentation for formula).
        my $importance = (($frequencies{$word} / %frequencies) * (log((($totalFrequency + @corpusWords) / 2) / (1 + $frequencyInCorpus) + 1)));

        $importances{$word} = $importance;

    }

    return %importances;

}

# The importances are relative, so they can be normalized to a scale of 0.5 - 100.
sub NormalizeImportances {

    my @keys = @{ $_[0] };
    my %importances = %{ $_[1] };

    my $denominator = $importances{ $keys[0] } - $importances{ $keys[ scalar @keys - 1 ] };

    foreach my $word (@keys) {
        
        $importances{$word} = sprintf("%.2f", (($importances{$word} - $importances{ $keys[ scalar @keys - 1 ] }) / $denominator) * 99.5) + 0.5;

    }

    return %importances;

}

# Get all the words of the input document in an array.
my @wordList = GetAllWords();
if (!$simplePrint) {
    print($language eq 'cze' ? "Načetl jsem " . @wordList . " slov z input dokumentu.\n" : "Loaded " . @wordList . " words from input document.\n");
}

# Get the entire Czech corpus in an array of hashes.
my @corpusWords = GetCzechCorpus();
if (!$simplePrint) {
    print($language eq 'cze' ? "Načetl jsem český korpus s " . @corpusWords . " slovy.\n" : "Loaded Czech corpus with " . @corpusWords . " words.\n");
}

# Remove the first 150 most frequent words (of the corpus) from the input text.
my @frequentCorpusWords = @corpusWords[ 0 .. 149 ];
my $countWithStopWords = @wordList;
@wordList = RemoveStopWords(\@wordList, \@frequentCorpusWords);
my $removedStopWords = ($countWithStopWords - @wordList);
if (!$simplePrint) {
    print($language eq 'cze' ? "Odstranil jsem " . $removedStopWords . " stop slov ze seznamu.\n" : "Removed " . $removedStopWords . " stop words from the word list.\n");
}

# Remove words that are 3 characters or less - these usually don't carry any content.
my $countWithShortWords = @wordList;
@wordList = RemoveShortWords(\@wordList);
my $removedShortWords = ($countWithShortWords - @wordList);
if (!$simplePrint) {
    print($language eq 'cze' ? "Odstranil jsem " . $removedShortWords . " krátkých slov ze seznamu.\n" : "Removed " . $removedShortWords . " short words from the word list.\n");
}

# Count the word frequencies.
my %frequencies = GetWordFrequencies(\@wordList);
if (!$simplePrint) {
    print($language eq 'cze' ? "Načetl jsem " . %frequencies . " unikátních slov z input dokumentu.\n" : "Loaded " . %frequencies . " unique words from input document.\n");
}

# Remove unsual words from the list.
my $countWithUnsualWords = %frequencies;
%frequencies = RemoveUnusualWords(\%frequencies, scalar @wordList);
my $removedUnusualWords = ($countWithUnsualWords - %frequencies);
if (!$simplePrint) {
    print($language eq 'cze' ? "Odstranil jsem " . $removedUnusualWords . " neobvyklých slov ze seznamu frekvencí.\n" : "Removed " . $removedUnusualWords . " unusual words from the frequencies list.\n");
}

# Assing an importance value to each word in %frequencies.
my %importances = CalculateImportanceValues(\%frequencies, \@corpusWords);
my @sortedKeyImportances = sort { $importances{$b} <=> $importances{$a} or $b cmp $a } keys %importances;

# Normalize importace value to the 0.5 - 100 range.
%importances = NormalizeImportances(\@sortedKeyImportances, \%importances);

# Print out the results to $output.
my $index = 1;
my $indexLimit = min(19, scalar @sortedKeyImportances - 1);
for my $word (@sortedKeyImportances[ 0 .. $indexLimit ]) {
    my $wordOutput = $simplePrint ? "$word\n" : "$index. $word ($importances{$word})\n";
    print($wordOutput);
    $index++;
}
