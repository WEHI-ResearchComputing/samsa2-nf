# samsa2-nf
Nextflow translation for [SAMSA2](https://github.com/transcript/samsa2) metatranscriptomics pipeline. Tailored for running on WEHI Milton. The translation is of the [master](https://github.com/transcript/samsa2/blob/master/bash_scripts/master_script.sh) script in the original pipeline.

## Usage

### Setup

After following the Samsa2 setup instructions, the working directory structure should look like:

```
.
├── full_databases
│   ├── New_Bac_Vir_Arc_RefSeq.dmnd
│   ├── New_Bac_Vir_Arc_RefSeq.fa
│   ├── RefSeq_bac.fa
│   ├── subsys_db.dmnd
│   ├── subsys_db.fa
│   └── viral_reference
├── input_files
│   ├── 48E_S68_L001_R1_001.fastq # input files follow *_R{1,2}_* pattern
│   ├── 48E_S68_L001_R2_001.fastq
│   ├── 48F_S69_L001_R1_001.fastq
│   ├── 48F_S69_L001_R2_001.fastq
|   ├── ...other input files...
├── programs
│   ├── diamond
│   ├── diamond-linux64.tar.gz
│   ├── diamond_manual.pdf
│   ├── diamond-sse2
│   ├── pear-0.9.10-linux-x86_64
│   ├── pear-0.9.10-linux-x86_64.tar.gz
│   ├── sortmerna-2.1
│   ├── sortmerna-2.1.tar.gz
│   ├── Trimmomatic-0.36
│   └── Trimmomatic-0.36.zip
└── python_scripts
    ├── DIAMOND_analysis_counter_mp.py # this is a parallel version of DIAMOND_analysis_counter.py
    ├── DIAMOND_analysis_counter.py
    ├── DIAMOND_subsystems_analysis_counter.py
    ├── raw_read_counter.py
    └── subsys_reducer.py
```
*NOTE* that `samsa2-master.nf` makes use of `DIAMOND_analysis_counter_mp.py` in this repository (not the original `DIAMOND_analysis_counter.py`). See the modifications section below.

### Run the pipeline

```bash
nextflow run samsa2-master.nf
```

### Parameters

```
nextfow run samsa2-master.nf
  --input_files <directory with pairs of reads>
  --python_scripts <directory with python scripts>
  --diamond_database <path to RefSeq db>
  --subsys_database <path to SubSys db>
  --output_dir <directory to store linked output files>
```

## Modifications from original

`DIAMOND_analysis_counter_mp.py` is modified from the original SAMSA2 pipeline. It's modified to make use of Python's `multiprocessing` module. Number of processes is set with `-t <no. of processes>` option. Currently, this produces identical results to the original in `-O` and `-F` mode (used in the original master script), and should produce the correct results for `-R`, but this hasn't been verified. `-SO` mode has not been checked either.

The DIAMOND blastx step has the `-b 12` and `-c 1` [performance options](https://github.com/bbuchfink/diamond/wiki/3.-Command-line-options#memory--performance-options) added. Respectively, these increase the number of block size and decrease the number of chunks from the default. Both of these changes have the net effect of increasing memory usage *substantially*, but reducing run times *substantially*. The maximum observed memory usage is 170GB, which Milton's nodes can easily satisfy, but may be problematic on other hardware.

The DIAMOND blastx step is also making use of `/vast/scratch/users/$USER/tmp`. This should be parameterised in the future.

## Output files

The output files by default will be placed in `output_files` with the `step_{1..5}_output` folders which should contain the same results as the original master script.

*NOTE* as Nextflow on WEHI's Milton HPC is configured to use the VAST Scratch as the working directory, to get around the 14-day deletion policy,`samsa2-master.nf` *copies* the results from the working directories to the `output_files` folder. 
