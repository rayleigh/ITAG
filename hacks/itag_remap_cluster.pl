#!/usr/bin/env perl
use strict;
use warnings;
use autodie ':all';

use Cwd;

use Storable qw/ nstore retrieve /;
use Data::Dumper;
use List::Util qw/ shuffle max /;

use Getopt::Std;

use File::Path qw/ make_path remove_tree /;

use Path::Class;

use Bio::SeqIO;

use CXGN::Tools::List qw/ balanced_split /;
use CXGN::ITAG::Pipeline;
use CXGN::ITAG::SeqSource::Fasta;

our %opt;
getopts('g:c:',\%opt) or usage();
###########

my $genomic_chunks = $opt{g} || 200;
my $cdna_chunks    = $opt{c} || 30;
my $batch_number   = 5;

###########


$SIG{__DIE__} = \&Carp::confess;

my $cdna_dir    = dir( 'input/cdna' );
my $genomic_dir = dir( 'input/genomic' );
my $jobs_dir    = dir( 'jobs' );

# and now we generate an all-versus-all pairing of genomic and cdna files
my @file_pair_sets = do {
    my $cdna_files    = generate_cdna_input   ( $cdna_chunks, $cdna_dir, $jobs_dir );
    my $genomic_files = generate_genomic_input( 'genomic.fa', $genomic_chunks, $genomic_dir, $jobs_dir );

    # now generate an all-vs-all array of pairs of files that need to
    # be against eachother, and do a balanced_split on that to batch
    # them into (at most) 200 cluster jobs
    balanced_split( 200, map { my $g = $_; map [ $_, $g ], @$cdna_files } @$genomic_files );
};

my @jobs;
my $job_number = 0;
foreach my $pairs ( @file_pair_sets ) {
    # each $pairs is an arrayref like [ [c,g],[c,g],[c,g], ... ]

    my $jobdir  = $jobs_dir->subdir( ++$job_number );

    print "job $job_number - $jobdir - ".@$pairs." pairs\n";

    my $donefile  = $jobdir->file('done');
    if( -f $donefile  ) {
	print "done, skipping.\n";
	next;
    }


    my $save_file = $jobdir->file('job.save');  #< file for saving the job record, so we can check if it's running
    my $job = eval{ retrieve( $save_file ) };

    if( $job && eval {$job->alive} ) {
	print "using existing, running job ".$job->job_id."\n";
    } else {
	$job = submit_job( $jobdir, $donefile, $pairs );
	nstore( $job, $save_file );
    }

    push @jobs, $job;

    $_->alive for @jobs;
}


sleep 10 while grep $_->alive, @jobs;

$_->cleanup for @jobs;

exit;

######### SUBS
# estimates the resources for each sequence name, used for giving resource hints to the job scheduler

sub estimate_vmem {
    my ( $cdna_file, $genomic_file ) = @_;

    my $cdna_size = -s $cdna_file
	or die "sanity check failed, no size found for cdna file $cdna_file";
    my $genomic_size = -s $genomic_file
	or die "sanity check failed, no size found for genomic file $genomic_file";

    my $megs = 2**20;
    my $vmem_est = sprintf('%0.0f',
			   (   200*$megs
			     + '5e-05' * $genomic_size * $cdna_size
                           )/$megs
			  );
    #print "cdna size: $cdna_size, seq size: $seq_size => vmem $vmem_est M\n";

    return $vmem_est;
}

sub generate_genomic_input {
    my $source_file = file( shift );
    my $chunk_count = shift;
    my $input_dir   = dir( shift );

    my $donefile = $input_dir->file('done');
    unless( -f $donefile ) {
	print "generating genomic input files...";
	$input_dir->rmtree;
	$input_dir->mkpath;

	chunk_fasta_file( $source_file, $chunk_count, $input_dir );

	$donefile->openw->print("done ".time."\n");
	print "done.\n";
    } else {
	print "using cached genomic input.\n";
    }
    my @files;
    $input_dir->recurse( callback => sub { $_ = shift; push @files, $_ if -f && /\.fa$/ } );
    return \@files;
}


sub chunk_fasta_file {
    my ( $file, $chunk_count, $dir, $make_name ) = @_;
    $dir = dir( $dir );
    $make_name ||= sub { my ($d,$chunk_num,$seq_list) = @_;
			 return $d->file( $chunk_num.'.fa')->stringify
		       };

    my $src = CXGN::ITAG::SeqSource::Fasta->new( file => $file );
    my $chunk_idx;
    foreach my $chunk ( balanced_split( $chunk_count, shuffle $src->all_seq_names ) ) {
	my $out = Bio::SeqIO->new( -format => 'fasta',
				   -file => '>'.$make_name->( $dir, ++$chunk_idx, $chunk ),
				  );
	foreach (@$chunk) {
	    my ($seq,undef) = $src->get_seq( $_ );
	    $out->write_seq( $seq );
	}
    }
}

sub generate_cdna_input {
    my $chunk_count = shift;
    my $input_dir = dir( shift );

    my $donefile = $input_dir->file('done');
    if( -f $donefile ) {
	print "using cached cdna input.\n";
	return _cdna_file_list( $input_dir );
    }

    print "generating cdna input...";

    system "rm -rf $input_dir";
    $input_dir->mkpath;

    my $pipe = CXGN::ITAG::Pipeline->open( version => 1 );
    my $batch = $pipe->batch( $batch_number );
    my $an = $pipe->analysis( 'renaming' );

    my $all_seqs = File::Temp->new;
    foreach ( sort $batch->seqlist ) {
	my (undef,undef,undef,$cdna_file) = $an->files_for_seq( $batch, $_ );
	next unless -f $cdna_file;
	my $fh = file( $cdna_file )->openr;
	$all_seqs->print( $_ ) while <$fh>;
    }

    chunk_fasta_file( $all_seqs, $chunk_count, $input_dir );

    $donefile->openw->print("done\n");
    print "done.\n";

    return _cdna_file_list( $input_dir );
}

sub _cdna_file_list {
    my $input_dir = shift;
    my @files;
    $input_dir->recurse( callback => sub { $_ = shift; push @files, $_ if -f && /\.fa$/ } );
    return \@files;
}


sub submit_job {
    my ( $jobdir, $donefile, $pairs ) = @_;

    system "rm -rf $jobdir";
    $jobdir->mkpath;

    my $pairs_file = $jobdir->file('pairs');
    { local $Data::Dumper::Indent = 0;
      local $Data::Dumper::Terse  = 1;
      my $pairs_fh  = $pairs_file->openw;
      $pairs_fh->say( Dumper [ "$_->[0]", "$_->[1]" ] ) for @$pairs;
    }

    my %job_record = ( pairs    => $pairs_file,
		       dir      => $jobdir->stringify,
		       donefile => $donefile->stringify,
		       script => <<'EOS',
		       use CXGN::Tools::Run;
                       use autodie ':all';

		       my $pair_number = 0;
                       open my $pairs, $j->{pairs};
                       while( my $p = <$pairs> ) {
                         $p = eval $p;
                         my ($cdna, $genomic) = @$p;
                         my $outfile = $j->{dir}.'/'.++$out_cnt.'.xml';
                         #system "echo $cdna, $genomic > $outfile"; next;
			 CXGN::Tools::Run->run( 'gth',
						'-xmlout',
						'-force', #overwrite output
						-minalignmentscore => '0.90',
						-mincoverage       => '0.90',
						-seedlength        => 16,
						-o                 => $outfile,
						-species           => 'arabidopsis',
						-cdna              => $cdna,
						-genomic           => $genomic,
			                      );
		       }
		       open my $f, '>', $j->{donefile};
                       print $f "done\n";
EOS
	             );

    my $vmem_est = max map estimate_vmem( $_->[0], $_->[1] ), @$pairs;

    my $jobfile = $jobdir->file('job.dat');
    nstore \%job_record, $jobfile;
    print "jobfile $jobfile\n";

    my $job = CXGN::Tools::Run->run_cluster( 'itag_wrapper',
					     'perl',
					     '-MStorable=retrieve',
					     -E => q|my $j = retrieve($ARGV[0]); eval $j->{script}; die $@ if $@|,
					     $jobfile,
					     {
						 temp_base => $jobdir,
						 vmem      => $vmem_est,
					     },
	                                   );

    print "submitted as ".$job->job_id."\n";

    return $job;
}