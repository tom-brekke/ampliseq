process ITSX_CUTASV {
    label 'process_medium'

    conda "bioconda::itsx=1.1.3"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/itsx:1.1.3--hdfd78af_1' :
        'biocontainers/itsx:1.1.3--hdfd78af_1' }"

    input:
    path fasta
    val outfile

    output:
    path outfile         , emit: fasta
    path "ASV_ITS_seqs.summary.txt", emit: summary
    path "ASV_ITS_seqs.*fasta", emit: fastas
    path "versions.yml"  , emit: versions
    path "*.args.txt"    , emit: args

    script:
    def args = task.ext.args ?: ''
    """
    ITSx \\
        -i $fasta \\
        $args \\
        --cpu $task.cpus \\
        -o ASV_ITS_seqs

    if [ ! -s $outfile ]; then
        echo "ERROR: No ITS regions found by ITSx. You might want to modify --cut_its and/or --its_partial" >&2
        exit 1
    fi

    # Generate a robust summary directly from FASTA counts.
    total=$(grep -c '^>' "$fasta" || true)
    kept=$(grep -c '^>' "$outfile" || true)
    skipped=$(( total - kept ))
    if [ "$skipped" -lt 0 ]; then
        skipped=0
    fi
    echo "ITSx extraction summary" > ASV_ITS_seqs.summary.txt
    echo "Number of sequences in input file: ${total:-0}" >> ASV_ITS_seqs.summary.txt
    echo "Sequences detected as ITS by ITSx: ${kept:-0}" >> ASV_ITS_seqs.summary.txt
    echo "Number of sequences skipped: ${skipped:-0}" >> ASV_ITS_seqs.summary.txt

    echo -e "ITSx\t$args" > ITSx.args.txt
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ITSx: \$( ITSx -h 2>&1 > /dev/null | tail -n 2 | head -n 1 | cut -f 2 -d ' ' )
    END_VERSIONS
    """
}
