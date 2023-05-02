#!/usr/bin/env nextflow

params.input_dir = "$projectDir/input_files"
params.python_scripts = "$projectDir/python_scripts"
params.programs = "$projectDir/programs"
params.diamond_database = "$projectDir/full_databases/New_Bac_Vir_Arc_RefSeq"
refseq_db = "${params.diamond_database}.fa"
params.subsys_database = "$projectDir/full_databases/subsys_db"
params.output_dir = "$projectDir/output_files"
step_1_output_dir = "$params.output_dir/step_1_output"
step_2_output_dir = "$params.output_dir/step_2_output"
step_3_output_dir = "$params.output_dir/step_3_output"
step_4_output_dir = "$params.output_dir/step_4_output"
step_5_output_dir = "$params.output_dir/step_5_output"

input_files = "${params.input_dir}/*_R{1,2}_*" // match everything else

// step 1
process TRIMMOMATIC {

    cpus 6
    memory '12 GB'
    publishDir step_1_output_dir, mode: 'copy'
    module 'trimmomatic'

    input:
    tuple val(sample_id), path(reads)

    output:
    tuple val("${sample_id}"), path("${sample_id}.cleaned.forward"), path("${sample_id}.cleaned.reverse")

    script:
    """
    trimmomatic PE -phred33 -threads $task.cpus "$reads" ${sample_id}.cleaned.forward ${sample_id}.cleaned.forward_unpaired ${sample_id}.cleaned.reverse ${sample_id}.cleaned.reverse_unpaired SLIDINGWINDOW:4:15 MINLEN:70
    """

}

// step 2
process PEAR {
    cpus 56
    memory '56 GB'
    publishDir step_2_output_dir, mode: 'copy'
    module 'pear/0.9.11'

    input:
    tuple val(sample_id), path(reads_cleaned_forward), path(reads_cleaned_reverse)

    output:
    tuple val("$sample_id"), path("${sample_id}.merged.assembled.fastq"), path("${sample_id}.merged.discarded.fastq"), path("${sample_id}.merged.unassembled.forward.fastq"), path("${sample_id}.merged.unassembled.reverse.fastq"), path("${sample_id}.merged.assembled.fastq.ribosomes.log")

    script:
    """
    pear -f $reads_cleaned_forward -r $reads_cleaned_reverse -j $task.cpus -o ${sample_id}.merged 2>&1 | tee ${sample_id}.merged.assembled.fastq.ribosomes.log
    """
}

// step 2.9
process RAWREADCOUNT {

    cpus 1
    memory '4 GB'
    publishDir step_2_output_dir, mode: 'copy'

    input:
    path(input_forward_reads)

    output:
    path 'raw_counts.txt'

    script:
    """
    for infile in $input_forward_reads; do python $params.python_scripts/raw_read_counter.py -I \$infile -O raw_counts.txt; done
    """

}

process SORTMERNA {

    cpus 24
    memory '12 GB'
    publishDir step_3_output_dir, mode: 'copy'

    input:
    tuple val(sample_id), path(assembled_fastq)

    output:
    tuple val(sample_id), path("${sample_id}.merged.ribodepleted.fastq")

    script:
    """
    ${params.programs}/sortmerna-2.1/sortmerna \
        -a $task.cpus \
        --ref ${params.programs}/sortmerna-2.1/rRNA_databases/silva-bac-16s-id90.fasta,${params.programs}/sortmerna-2.1/index/silva-bac-16s-db \
        --reads $assembled_fastq \
        --aligned ${assembled_fastq}.ribosomes \
        --other ${sample_id}.merged.ribodepleted \
        --fastx \
        --log \
        -v
    """
}

process DIAMOND_REFSEQ {

    cpus 70
    memory '170 GB'
    publishDir "${step_4_output_dir}/RefSeq_results", mode: 'copy'

    input:
    tuple val(sample_id), path(ribodepleted_fastq)

    output:
    tuple val(sample_id), path("${sample_id}.merged.RefSeq_annotated"), path("${ribodepleted_fastq}.RefSeq.daa")

    script:
    """
    ${params.programs}/diamond blastx --db $params.diamond_database -q $ribodepleted_fastq -a ${ribodepleted_fastq}.RefSeq -t /vast/scratch/users/\$USER/tmp -k 1 -p $task.cpus -b 12 -c 1
    ${params.programs}/diamond view --daa ${ribodepleted_fastq}.RefSeq.daa -o ${sample_id}.merged.RefSeq_annotated -f tab -p $task.cpus
    """

}

process DIAMOND_SUBSYS {

    cpus 24
    memory '170 GB'
    publishDir "${step_4_output_dir}/Subsystems_results", mode: 'copy'

    input:
    tuple val(sample_id), path(ribodepleted_fastq)

    output:
    tuple val(sample_id), path("${sample_id}.merged.Subsys_annotated"), path("${ribodepleted_fastq}.Subsys.daa")

    script:
    """
    ${params.programs}/diamond blastx --db $params.subsys_database -q $ribodepleted_fastq -a ${ribodepleted_fastq}.Subsys -t /vast/scratch/users/\$USER/tmp -k 1 -p $task.cpus -b 12 -c 1
    ${params.programs}/diamond view --daa ${ribodepleted_fastq}.Subsys.daa -o ${sample_id}.merged.Subsys_annotated -f tab -p $task.cpus
    """


}

process REFSEQ_ANALYSISCOUNTER_FUNC {

    cpus 46
    memory '64 GB'
    publishDir "${step_5_output_dir}/RefSeq_results/func_results", mode: 'copy'

    input:
    tuple val(sample_id), path(refseq_annotated)

    output:
    tuple val(sample_id), path("${sample_id}.merged.*.tsv")

    script:
    """
    python ${params.python_scripts}/DIAMOND_analysis_counter_mp.py -I ${refseq_annotated} -D $refseq_db -F -t $task.cpus
    """
}

process REFSEQ_ANALYSISCOUNTER_ORG {

    cpus 46
    memory '64 GB'
    publishDir "${step_5_output_dir}/RefSeq_results/org_results", mode: 'copy'

    input:
    tuple val(sample_id), path(refseq_annotated)

    output:
    tuple val(sample_id), path("${sample_id}.merged.*.tsv")

    script:
    """
    python ${params.python_scripts}/DIAMOND_analysis_counter_mp.py -I ${refseq_annotated} -D $refseq_db -O -t $task.cpus
    """
}

process SUBSYS_ANALYSIS_COUNTER {

    cpus 2
    memory '64 GB'
    publishDir "${step_5_output_dir}/Subsystems_results/receipts", pattern: '*.receipt', mode: 'copy'

    input:
    tuple val(sample_id), path(subsys_annotated)

    output:
    tuple val(sample_id), path('*.hierarchy'), path('*.receipt')

    script:
    """
    python ${params.python_scripts}/DIAMOND_subsystems_analysis_counter.py \
        -I $subsys_annotated \
        -D ${params.subsys_database}.fa \
        -O ${subsys_annotated}.hierarchy \
        -P ${subsys_annotated}.receipt
    """

}

process SUBSYS_REDUCER {

    cpus 2
    memory '64 GB'
    publishDir "${step_5_output_dir}/Subsystems_results", mode: 'copy'

    input:
    tuple val(sample_id), path(subsys_annotated_hierarchy)

    output:
    tuple val(sample_id), path('*.reduced')

    script:
    """
    python ${params.python_scripts}/subsys_reducer.py -I $subsys_annotated_hierarchy
    """
}

// process R {

// }

workflow {


    infiles_ch = Channel.fromPath(input_files)

    Channel
        .fromFilePairs(input_files, checkIfExists: true)
        .set { read_pairs_ch }

    trim_ch = TRIMMOMATIC(read_pairs_ch)

    pear_ch = PEAR(trim_ch)

    forward_reads_ch = trim_ch.map{it[1]}.collect(flat: false)
    raw_counts_ch = RAWREADCOUNT(forward_reads_ch)

    sortmerna_input_ch = pear_ch.map{[it[0],it[1]]}
    sortmerna_ch = SORTMERNA(sortmerna_input_ch)

    // REFSEQ
    diamond_refseq_ch = DIAMOND_REFSEQ(sortmerna_ch)

    refseq_analysiscounter_input_ch = diamond_refseq_ch.map{[it[0],it[1]]}
    refseq_analysiscounter_func_ch = REFSEQ_ANALYSISCOUNTER_FUNC(refseq_analysiscounter_input_ch)
    refseq_analysiscounter_org_ch = REFSEQ_ANALYSISCOUNTER_ORG(refseq_analysiscounter_input_ch)

    // SUBSYS
    diamond_subsys_ch = DIAMOND_SUBSYS(sortmerna_ch)
    subsys_analysiscounter_input_ch = diamond_subsys_ch.map{[it[0],it[1]]}
    subsys_analysiscounter_ch = SUBSYS_ANALYSIS_COUNTER(subsys_analysiscounter_input_ch)
    subsys_reducer_input_ch = subsys_analysiscounter_ch.map{[it[0],it[1]]}
    subsys_reducer_ch = SUBSYS_REDUCER(subsys_reducer_input_ch)
}
