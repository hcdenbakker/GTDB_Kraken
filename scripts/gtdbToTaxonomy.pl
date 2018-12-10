#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;
use Bio::Perl;
use File::Basename qw/basename/;
use File::Copy qw/mv cp/;
use File::Find qw/find/;

my %rank=(
  d => "domain",
  p => "phylum",
  c => "class",
  o => "order",
  f => "family",
  g => "genus",
  s => "species",
);

# Different logging functions to STDERR
sub logmsg   {print STDERR "@_";} # simple message
sub logmsgLn {logmsg "@_\n"; }    # newline
sub logmsgBg {logmsg "$0 @_"}     # with script name (BG: beginning of line)

exit main();

sub main{

  my $settings={};
  GetOptions($settings, qw(infile=s --sequence-dir=s help)) or die $!;
  die usage() if($$settings{help});
  $$settings{infile} ||= die "ERROR: need --infile";

  my $fastaIndex = fastaIndex($$settings{'sequence-dir'});
  logmsgBg "Loaded ".scalar(keys(%$fastaIndex))." fasta files into the index\n";

  mkdir "taxonomy";
  mkdir "library";
  mkdir "library/gtdb";

  open(my $nodesFh, ">", "taxonomy/nodes.dmp") or die "ERROR writing to nodes.dmp";
  open(my $namesFh, ">", "taxonomy/names.dmp") or die "ERROR writing to names.dmp";

  my $rootTaxid=1;
  my %root=(
    taxid          => $rootTaxid,
    scientificName => "root",
    rank           => "root",
    parent         => $rootTaxid,
  );

  my $taxonCounter=1;
  my %taxon=(root=>\%root);

  open(my $inFh, "<", $$settings{infile}) or die "ERROR: could not read $$settings{infile}: $!";
  while(my $line=<$inFh>){
    next if($line=~/^\s*#/);
    chomp $line;
    my($asmid,$lineageStr)=split /\t/, $line; 
    my $assemblyId = $asmid;
    $assemblyId=~s/^RS_//;   # remove prefix RS_
    $assemblyId=~s/^GB_//;   # remove prefix RS_
    $assemblyId=~s/\.\d+$//; # remove version

    logmsgBg "Loading ". $assemblyId.", ".substr($lineageStr,0,20)."...".substr($lineageStr,-40,40)."\n";
    my @lineage=split(/;/, $lineageStr); 
    for(my $i=0;$i<@lineage;$i++){
      my $name = $lineage[$i];
      my ($rank,$scientificName) = split(/__/, $name);

      # If the taxon has not been defined yet, then write it up
      if(!defined($taxon{$name})){
        my $taxid = ++$taxonCounter;
        my $rank   = $rank{lc($rank)};

        my $parent;
        if($rank eq "domain"){
          $parent = $rootTaxid;
        } else {
          $parent = $taxon{$lineage[$i-1]}{taxid};
        }

        $taxon{$name} = {
          taxid          => $taxid,
          scientificName => $scientificName,
          rank           => $rank,
          parent         => $parent,
          asm            => $asmid,
        };

        print $nodesFh join("\t|\t", $taxid, $parent, $rank, "", 0, 1, 11, 1, 0, 1, 1, 0)."\t|\n";
        print $namesFh join("\t|\t", $taxid, $scientificName, "", "scientific name")."\t|\n";
        
      }
    }

    # Download the genome with the last taxid
    my $taxid = $taxon{$lineage[-1]}{taxid};
    my $filename = "library/gtdb/$assemblyId.fna";
    logmsgBg "  finding it ($assemblyId)...";
    if(-e $filename){
      logmsgLn "file present, not downloading again.";
      next;
    }

    # Copy or download the file
    if($$fastaIndex{$assemblyId}){
      logmsg "copying from $$fastaIndex{$assemblyId}...";
      #cp($$fastaIndex{$assemblyId}, "$filename.tmp") or die $!;
      link($$fastaIndex{$assemblyId}, "$filename.tmp") or die $!;
    } else {
      logmsg "from NCBI using esearch ($assemblyId)...";
      system("esearch -db assembly -query $assemblyId | elink -target nuccore | efetch -format fasta > $filename.tmp");
      my $filesize = (stat "$filename.tmp")[7];
      if($filesize < 1){
        warn "ERROR downloading $assemblyId with exit code $?: $!. To skip this error, comment this line in the input file.\n";
      }
    }
    
    # Replace with taxids
    my $in=Bio::SeqIO->new(-file=>"$filename.tmp", -format=>"fasta");
    my $out=Bio::SeqIO->new(-file=>">$filename.kraken", -format=>"fasta");
    my %seenSeq=();
    while(my $seq=$in->next_seq){
      next if($seenSeq{$seq->seq}++); # avoid duplicate contigs within a genome
      my $id=$seq->id;
      $seq->desc(" "); # unset the description fields
      $seq->id("$id|kraken:taxid|$taxid");
      $out->write_seq($seq);
    }

    # Cleanup
    unlink("$filename.tmp"); # cleanup
    mv("$filename.kraken",$filename);
    logmsgLn "got it!\n";
  }

  close $inFh;
  logmsgLn;

  close $nodesFh;
  close $namesFh;


  return 0;
}

# Find all fasta files in a given directory
sub fastaIndex{
  my($dir,$settings)=@_;
  my %fasta;
  find({follow=>1, no_chdir=>1, wanted=>sub{
    return if(!-e $File::Find::name);
    return if($File::Find::name !~ /\.(fna|fasta|fa|fsa|fas)$/);

    # Transform the accession to simply the number.
    my $accession=basename($File::Find::name);
    # Remove any other extensions actually
    $accession=~s/\..+$//;
    # remove leading prefix with underscore, e.g., GCA_
    #$accession=~s/^.*_+//;
    # Remove 0 padding
    #$accession=~s/^0+//;

    if($fasta{$accession}){
      die "ERROR: found accession $accession at least twice:\n  ".$File::Find::name."\n  $fasta{$accession}\n";
    }

    $fasta{$accession} = $File::Find::name;
  }},$dir);

  return \%fasta;
}

sub usage{
  "Usage: perl [--sequence-dir fasta] --infile gtdb.txt $0
  Where gtdb.txt is a two column file with assembly ID and semicolon-delimited lineage
  Outputs two folders for taxonomy and library of fasta files.

  --sequence-dir       (optional) Local directory from which to find fasta files.
                       Each fasta filename must match against the first column from
                       --infile.  Fasta files must be uncompressed.
                       Fasta file extensions can be: fna, fasta, fa, fsa, fas
  "
}

