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
    module 'trimmomatic/0.36'
    container 'quay.io/biocontainers/trimmomatic:0.36--6'

    input:
    tuple val(sample_id), path(reads)

    output:
    tuple val("${sample_id}"), path("${sample_id}.cleaned.forward"), path("${sample_id}.cleaned.reverse")

    shell:
    """
    trimmomatic PE \
        -phred33 \
        -threads !{task.cpus} \
        "!{reads}" \
        !{sample_id}.cleaned.forward \
        !{sample_id}.cleaned.forward_unpaired \
        !{sample_id}.cleaned.reverse \
        !{sample_id}.cleaned.reverse_unpaired \
        SLIDINGWINDOW:4:15 MINLEN:70
    """

}

// step 2
process PEAR {
    cpus 56
    memory '1 GB'
    publishDir step_2_output_dir, mode: 'copy'
    module 'pear/0.9.11'
    container 'quay.io/biocontainers/pear:0.9.6--h67092d7_8'

    input:
    tuple val(sample_id), path(reads_cleaned_forward), path(reads_cleaned_reverse)

    output:
    tuple val("$sample_id"), path("${sample_id}.merged.assembled.fastq"), path("${sample_id}.merged.discarded.fastq"), path("${sample_id}.merged.unassembled.forward.fastq"), path("${sample_id}.merged.unassembled.reverse.fastq"), path("${sample_id}.merged.assembled.fastq.ribosomes.log")

    shell:
    '''
    pear --forward-fastq !{reads_cleaned_forward} \
         --reverse-fastq !{reads_cleaned_reverse} \
         --threads !{task.cpus} \
         --output !{sample_id}.merged 2>&1 | tee !{sample_id}.merged.assembled.fastq.ribosomes.log
    '''
}

// step 2.9
process RAWREADCOUNT {

    cpus 1
    memory '500 MB'
    publishDir step_2_output_dir, mode: 'copy'

    input:
    path(input_forward_reads)

    output:
    path 'raw_counts.txt'

    shell:
    '''
    for infile in !{input_forward_reads}
    do 
        python !{params.python_scripts}/raw_read_counter.py -I $infile -O raw_counts.txt
    done
    '''

}

process SORTMERNA {

    cpus 24
    memory '2 GB'
    publishDir step_3_output_dir, mode: 'copy'
    container 'quay.io/biocontainers/sortmerna:2.1b--0'

    input:
    tuple val(sample_id), path(assembled_fastq)

    output:
    tuple val(sample_id), path("${sample_id}.merged.ribodepleted.fastq")

    shell:
    """
    sortmerna \
        -a !{task.cpus} \
        --ref !{params.programs}/sortmerna-2.1/rRNA_databases/silva-bac-16s-id90.fasta,!{params.programs}/sortmerna-2.1/index/silva-bac-16s-db \
        --reads !{assembled_fastq} \
        --aligned !{assembled_fastq}.ribosomes \
        --other !{sample_id}.merged.ribodepleted \
        --fastx \
        --log \
        -v
    """
}

process DIAMOND_REFSEQ {

    cpus 70
    memory '170 GB'
    publishDir "${step_4_output_dir}/RefSeq_results", mode: 'copy'
    container 'quay.io/biocontainers/diamond:0.8.36--h2e03b76_5'

    input:
    tuple val(sample_id), path(ribodepleted_fastq)

    output:
    tuple val(sample_id), path("${sample_id}.merged.RefSeq_annotated"), path("${ribodepleted_fastq}.RefSeq.daa")

    shell:
    '''
    diamond blastx \
        --db !{params.diamond_database} \
        --query !{ribodepleted_fastq} \
        --daa !{ribodepleted_fastq}.RefSeq \
        --tmpdir . \
        --max-target-seqs 1 \
        --threads !task.cpus \
        --block-size 12 \
        --index-chunks 1

    diamond view \
        --daa !{ribodepleted_fastq}.RefSeq.daa \
        --out !{sample_id}.merged.RefSeq_annotated \
        --outfmt tab \
        --threads !task.cpus
    '''

}

process DIAMOND_SUBSYS {

    cpus 24
    memory '64 GB'
    publishDir "${step_4_output_dir}/Subsystems_results", mode: 'copy'
    container 'quay.io/biocontainers/diamond:0.8.36--h2e03b76_5'

    input:
    tuple val(sample_id), path(ribodepleted_fastq)

    output:
    tuple val(sample_id), path("${sample_id}.merged.Subsys_annotated"), path("${ribodepleted_fastq}.Subsys.daa")

    shell:
    '''
    diamond blastx \
        --db !{params.subsys_database} \
        --query !{ribodepleted_fastq} \
        --daa !{ribodepleted_fastq}.Subsys \
        --tmpdir . \
        --max-target-seqs 1 \
        --threads !{task.cpus} \
        --block-size 12 \
        --index-chunks 1

    diamond view \
        --daa !{ribodepleted_fastq}.Subsys.daa \
        --out !{sample_id}.merged.Subsys_annotated \
        --outfmt tab \
        --threads !{task.cpus}
    '''


}

process REFSEQ_ANALYSISCOUNTER_FUNC {

    cpus 46
    memory '64 GB'
    publishDir "${step_5_output_dir}/RefSeq_results/func_results", mode: 'copy'

    input:
    tuple val(sample_id), path(refseq_annotated)

    output:
    tuple val(sample_id), path("${sample_id}.merged.*.tsv")

    shell:
    '''
    python !{params.python_scripts}/DIAMOND_analysis_counter_mp.py \
        -I !{refseq_annotated} \
        -D !{refseq_db} \
        -F \
        -t !{task.cpus}
    '''
}

process REFSEQ_ANALYSISCOUNTER_ORG {

    cpus 46
    memory '64 GB'
    publishDir "${step_5_output_dir}/RefSeq_results/org_results", mode: 'copy'

    input:
    tuple val(sample_id), path(refseq_annotated)

    output:
    tuple val(sample_id), path("${sample_id}.merged.*.tsv")

    shell:
    '''
    python !{params.python_scripts}/DIAMOND_analysis_counter_mp.py \
        -I !{refseq_annotated} \
        -D !{refseq_db} \
        -O \
        -t !{task.cpus}
    '''
}

process SUBSYS_ANALYSIS_COUNTER {

    cpus 1
    memory '4 GB'
    publishDir "${step_5_output_dir}/Subsystems_results/receipts", pattern: '*.receipt', mode: 'copy'

    input:
    tuple val(sample_id), path(subsys_annotated)

    output:
    tuple val(sample_id), path('*.hierarchy'), path('*.receipt')

    shell:
    '''
    python !{params.python_scripts}/DIAMOND_subsystems_analysis_counter.py \
        -I !{subsys_annotated} \
        -D !{params.subsys_database}.fa \
        -O !{subsys_annotated}.hierarchy \
        -P !{subsys_annotated}.receipt
    '''

}

process SUBSYS_REDUCER {

    cpus 1
    memory '1 GB'
    publishDir "${step_5_output_dir}/Subsystems_results", mode: 'copy'

    input:
    tuple val(sample_id), path(subsys_annotated_hierarchy)

    output:
    tuple val(sample_id), path('*.reduced')

    shell:
    '''
    python !{params.python_scripts}/subsys_reducer.py \
        -I !{subsys_annotated_hierarchy}
    '''
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

    raw_counts_ch = trim_ch.map{it[1]}.collect(flat: false) | RAWREADCOUNT

    sortmerna_ch = pear_ch.map{[it[0],it[1]]} | SORTMERNA

    // REFSEQ
    diamond_refseq_ch = DIAMOND_REFSEQ(sortmerna_ch)

    refseq_analysiscounter_input_ch = diamond_refseq_ch.map{[it[0],it[1]]}
    refseq_analysiscounter_func_ch = REFSEQ_ANALYSISCOUNTER_FUNC(refseq_analysiscounter_input_ch)
    refseq_analysiscounter_org_ch = REFSEQ_ANALYSISCOUNTER_ORG(refseq_analysiscounter_input_ch)

    // SUBSYS
    diamond_subsys_ch = DIAMOND_SUBSYS(sortmerna_ch)
    subsys_analysiscounter_ch = diamond_subsys_ch.map{[it[0],it[1]]} | SUBSYS_ANALYSIS_COUNTER
    subsys_reducer_ch = subsys_analysiscounter_ch.map{[it[0],it[1]]} | SUBSYS_REDUCER
}
