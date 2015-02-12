package Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveSubmitAnalysis;

use strict;
use warnings;
use feature 'say';

use Bio::EnsEMBL::Analysis::RunnableDB;
use Bio::EnsEMBL::Pipeline::Analysis;
use Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Pipeline::Hive::HiveInputIDFactory;
use Bio::EnsEMBL::Pipeline::DBSQL::StateInfoContainer;
use Bio::EnsEMBL::Utils::Exception qw(warning throw);
use parent ('Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveBaseRunnableDB');

sub fetch_input {
  my $self = shift;
  $self->db($self->get_dba($self->param('reference_db')));
  return 1;
}

sub run {
  my $self = shift;

  if (!($self->param('slice')) && !($self->param('single')) && !($self->param('file')) &&
      !($self->param('translation_id')) && !($self->param('hap_pair')) && !($self->param('chunk'))
     ) {
    throw("Must define input as either contig, slice, file, translation_id ".
          "single, seq_level or top_level or hap_pair");
  }

  if($self->param('slice') && $self->param('chunk')) {
    throw("You have selected both the slice and the chunk file, select one or the other");
  }

  unless($self->param('chunk')) {
    my $input_id_factory = new Bio::EnsEMBL::Pipeline::Hive::HiveInputIDFactory
    (
     -db => $self->db(),
     -slice => $self->param('slice'),
     -single => $self->param('single'),
     -file => $self->param('file'),
     -translation_id => $self->param('translation_id'),
     -seq_level => $self->param('seq_level'),
     -top_level => $self->param('top_level'),
     -include_non_reference => $self->param('include_non_reference'),
     -dir => $self->param('dir'),
     -regex => $self->param('regex'),
     -single_name => 'genome', # Don't know why this is set this way
     -logic_name => $self->param('logic_name'),
     -input_id_type => $self->param('input_id_type'),
     -coord_system => $self->param('coord_system_name'),
     -coord_system_version => $self->param('coord_system_version'),
     -slice_size => $self->param('slice_size'),
     -slice_overlaps => $self->param('slice_overlap'),
     -seq_region_name => $self->param('seq_region_name'),
     -hap_pair => $self->param('hap_pair'),
    );

    $input_id_factory->generate_input_ids;
    $self->{'input_id_factory'} = $input_id_factory;
  } else {

    my $input_file;
    if($self->param_is_defined('input_file_path')) {
      $input_file = $self->param('input_file_path');
    } else {
         $input_file = $self->input_id;
         unless($input_file =~ /" => "([^"]+)"}$/) {
           throw("No input file parameter passed in, therefore used job input id. Could not parse value out of job input id:\n".$input_file);
         }
      $input_file = $1;
    }

    unless(-e $input_file) {
      throw("Your input file '".$input_file."' does not exist!!!");
    }

    my $chunk_dir = $self->param('chunk_output_dir');
    my $chunk_num = $self->param('num_chunk');
    if($chunk_num) {
      make_chunk_files($input_file,$chunk_dir,$chunk_num);
    }
    $self->create_chunk_ids($chunk_dir,$input_file);
  }
  return 1;
}

sub make_chunk_files {
  my ($input_file,$chunk_dir,$chunk_num) = @_;
  unless(-e $chunk_dir) {
    `mkdir -p $chunk_dir`;
  }

  `/software/ensembl/bin/fastasplit_random $input_file $chunk_num $chunk_dir`;
}

sub create_chunk_ids {
  my ($self,$chunk_dir,$input_file) = @_;
  $input_file =~ /[^\/]+$/;
  $input_file = $&;
  $input_file =~ s/\.[^\.]+$//;

  my @chunk_array = glob $chunk_dir."/".$input_file."_chunk_*";
  for(my $i=0; $i < scalar@chunk_array; $i++) {
    $chunk_array[$i] =~ /[^\/]+$/;
    $chunk_array[$i] = $&;
  }
  $self->{'chunk_ids'} = \@chunk_array;
}

sub write_output {
  my $self = shift;

  my $output_ids;
  unless($self->param('chunk')) {
    $output_ids = $self->{'input_id_factory'}->input_ids();
  } else {
    $output_ids = $self->{'chunk_ids'};
  }
  unless(scalar(@{$output_ids})) {
    warning("No input ids generated for this analysis!");
  }


  foreach my $id (@{$output_ids}) {

    if($self->param_is_defined('skip_mito') && ($self->param('skip_mito') == 1 || $self->param('skip_mito') eq 'yes') &&
       $id =~ /^.+\:.+\:MT\:/) {
       next;
    }

    say "Output id: ".$id;
    my $output_hash = {};
    $output_hash->{'iid'} = $id;
    $self->dataflow_output_id($output_hash,1);
  }

  return 1;
}

sub db {
  my ($self, $value) = @_;
  if($value){
    $self->{'dbadaptor'} = $value;
  }
  return $self->{'dbadaptor'};
}

sub get_dba {
   my ($self,$connection_info) = @_;
   my $dba;

   if (ref($connection_info)=~m/HASH/) {

       $dba = new Bio::EnsEMBL::DBSQL::DBAdaptor(
                                                  %$connection_info,
                                                );
   }

  $dba->dbc->disconnect_when_inactive(1) ;
  return $dba;

}

sub input_ids {
 my ($self,$value) = @_;

  if (defined $value) {
    $self->{'input_ids'} = $value;
  }

  if (exists($self->{'input_ids'})) {
    return $self->{'input_ids'};
  }

  else {
    return undef;
  }

}

1;