=head1 NAME

CXGN::ITAG::Release::Series2 - data model for the second generation of
ITAG release structures, such as ITAG2

=head1 BASE CLASS

L<CXGN::ITAG::Release>

=cut

package CXGN::ITAG::Release::Series2;
use strict;
use warnings;

use Hash::Util qw/lock_keys lock_hash/;

use base 'CXGN::ITAG::Release';

=head2 get_all_files

  Usage: my $all = $rel->get_all_files
  Desc : get hashref of info for all files
  Args : none
  Ret  : hashref as
         {  shortname => file info hashref,
            ...
         }
  Side Effects: none

=head3 File Shortnames

  genomic_fasta
  cdna_fasta
  cds_fasta
  protein_fasta
  contig_gff3
  models_gff3
  genefinders_gff3
  functional_prot_gff3
  cdna_algn_gff3
  combi_genomic_gff3
  contig_members_sol
  sol_gb_mapping
  readme
  ...

=cut

sub get_all_files {
  my ($self) = @_;

  $self->{files} ||=
    {
     genomic_fasta        => { file => $self->_assemble_release_filename("genomic","fasta"),
			       desc => 'fasta-format sequence file of genomic contig sequences.',
			       type => 'fasta',
			       seq_type => 'genomic',
			     },
     cdna_fasta           => { file => $self->_assemble_release_filename("cdna","fasta"),
			       desc => 'fasta-format sequence file of cDNA sequences.',
			       type => 'fasta',
			       seq_type => 'cdna',
			     },
     cds_fasta            => { file => $self->_assemble_release_filename("cds","fasta"),
			       desc => 'fasta-format sequence file of CDS sequences.',
			       type => 'fasta',
			       seq_type => 'cds',
			     },
     protein_fasta        => { file => $self->_assemble_release_filename("proteins","fasta"),
			       desc => 'fasta-format sequence file of protein sequences.',
			       type => 'fasta',
			       seq_type => 'protein',
			     },
     models_gff3          => { file => $self->_assemble_release_filename("gene_models","gff3"),
			       desc => 'GFF version 3 file containing gene models in this release.',
			       type => 'gff3',
			       seq_type => 'genomic',
			     },
     genefinders_gff3     => { file => $self->_assemble_release_filename("de_novo_gene_finders","gff3"),
			       desc => 'GFF version 3 file containing predictions from several de novo gene finders.  These are intermediate data, used by EuGene to decide the final consensus gene models.',
			       type => 'gff3',
			       seq_type => 'genomic',
			     },
     sgn_data_gff3        => { file => $self->_assemble_release_filename("sgn_data","gff3"),
			       desc => 'GFF version 3 file containing alignments to sequences related to data on SGN.  Currently contains alignments to SGN unigenes, SGN marker sequences, and SGN locus sequences.',
			       type => 'gff3',
			       seq_type => 'genomic',
			     },
     genomic_reagents_gff3=> { file => $self->_assemble_release_filename("genomic_reagents","gff3"),
			       desc => 'GFF version 3 file containing alignments to other genomic sequences from tomato: genomic clones, other genome builds, etc.',
			       type => 'gff3',
			       seq_type => 'genomic',
			     },
     other_genomes_gff3   => { file => $self->_assemble_release_filename("other_genomes","gff3"),
			       desc => 'GFF version 3 file containing alignments to genomic sequences from other organisms.',
			       type => 'gff3',
			       seq_type => 'genomic',
			     },
     functional_prot_gff3 => { file => $self->_assemble_release_filename("protein_functional","gff3" ),
			       desc => 'GFF version 3 file containing functional annotations to protein sequences.',
			       type => 'gff3',
			       seq_type => 'protein',
			     },
     cdna_algn_gff3      =>  { file => $self->_assemble_release_filename("cdna_alignments","gff3" ),
			       desc => 'GFF version 3 file containing alignments of existing EST and cDNA sequences to the genome.',
			       type => 'gff3',
			       seq_type => 'genomic',
			     },
     combi_genomic_gff3   => { file => $self->_assemble_release_filename("genomic_all","gff3"),
			       desc => 'GFF version 3 file containing all genomic annotations in this release.',
			       type => 'gff3',
			       seq_type => 'genomic',
			     },
     readme               => { file => $self->_assemble_release_filename("README","txt"),
			       desc => 'Overview of the release, with some statistics.',
			       type => 'txt',
			       seq_type => '',
			     },
    };
  lock_hash(%$_) foreach values %{$self->{files}};
  lock_hash(%{$self->{files}});
  return $self->{files};
}


1;

