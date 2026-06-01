process ASSIGNSH {
    tag "${asvtable}"
    label 'process_low'

    conda "conda-forge::pandas=1.1.5 conda-forge::python=3.9.1"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/pandas:1.1.5':
        'biocontainers/pandas:1.1.5' }"

    input:
    path asvtable
    path sh_info
    tuple val(meta), path(blastfile)
    val  outtable

    output:
    path outtable        , emit: tsv
    path "versions.yml"  , emit: versions


    script:
    def args = task.ext.args ?: ''
    def sh_info_list = sh_info instanceof List ? sh_info : [sh_info]
    def sh_seq2sh = sh_info_list.find { file_item -> file_item.toString().toLowerCase().contains('seq2sh') } ?: sh_info_list[0]
    def sh_tax = sh_info_list.find { file_item ->
        def name = file_item.toString().toLowerCase()
        name.contains('shs.tax') || name.contains('sh.tax')
    } ?: (sh_info_list.size() > 1 ? sh_info_list[1] : sh_info_list[0])
    """
    add_sh_to_taxonomy.py $sh_seq2sh $sh_tax $asvtable $blastfile $outtable $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version 2>&1 | sed 's/Python //g')
        pandas: \$(python -c "import pkg_resources; print(pkg_resources.get_distribution('pandas').version)")
    END_VERSIONS
    """
}
