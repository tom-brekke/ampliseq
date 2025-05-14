/*
 * Taxonomic classification with DADA2
 */

include { CUTADAPT as CUTADAPT_TAXONOMY  } from '../../modules/nf-core/cutadapt/main'
include { VSEARCH_USEARCHGLOBAL          } from '../../modules/nf-core/vsearch/usearchglobal/main'

include { DADA2_TAXONOMY                               } from '../../modules/local/dada2_taxonomy'
include { DADA2_ADDSPECIES                             } from '../../modules/local/dada2_addspecies'
include { FORMAT_TAXRESULTS as FORMAT_TAXRESULTS_STD   } from '../../modules/local/format_taxresults'
include { FORMAT_TAXRESULTS as FORMAT_TAXRESULTS_ADDSP } from '../../modules/local/format_taxresults'
include { ASSIGNSH                                     } from '../../modules/local/assignsh'

include { makeComplement                 } from '../../subworkflows/local/utils_nfcore_ampliseq_pipeline'

workflow DADA2_TAXONOMY_WF {
    take:
    ch_assigntax
    ch_addspecies
    val_dada_ref_taxonomy
    ch_fasta
    ch_full_fasta
    taxlevels
    val_dada_assign_chunksize

    main:
    ch_versions_dada_taxonomy = Channel.empty()

    // Set cutoff to use for SH assignment and path to SH taxonomy file
    if ( params.addsh ) {
        vsearch_cutoff = 0.985
        ch_shinfo = Channel.fromList(params.dada_ref_databases[params.dada_ref_taxonomy]["shfile"]).map { file(it) }
    }

    //cut taxonomy to expected amplicon
    if (params.cut_dada_ref_taxonomy) {
        ch_assigntax
            .map {
                db ->
                    def meta = [:]
                    meta.single_end = true
                    meta.id = "assignTaxonomy"
                    meta.fw_primer = params.FW_primer
                    meta.rv_primer_revcomp = makeComplement ( "${params.RV_primer}".reverse() )
                    [ meta, db ] }
            .set { ch_assigntax }
        CUTADAPT_TAXONOMY ( ch_assigntax ).reads
            .map { meta, db -> db }
            .set { ch_assigntax }
        ch_versions_dada_taxonomy = ch_versions_dada_taxonomy.mix( CUTADAPT_TAXONOMY.out.versions )
    }

    //set file name prefix
    if (params.cut_its == "none") {
        ASV_tax_name = "ASV_tax"
    } else {
        ASV_tax_name = "ASV_ITS_tax"
    }

    // Split sequences into chunks
    ch_fasta
        .splitFasta(by: val_dada_assign_chunksize, file: true)
        .set { ch_fasta_chunks }

    // Prepare channels for constant inputs
    ch_assigntax      = Channel.value(path('your_database.fa')) // or however you're setting this
    ch_outfile_suffix = Channel.value(".${ASV_tax_name}.${val_dada_ref_taxonomy}")
    ch_taxlevels_val  = Channel.value(taxlevels)

    // Combine chunked fasta with constant values
    ch_fasta_chunks
        .combine(ch_assigntax, ch_outfile_suffix, ch_taxlevels_val)
        .set { ch_taxonomy_input }

    // DADA2 assignTaxonomy per chunk
    DADA2_TAXONOMY(ch_taxonomy_input)
    ch_versions_dada_taxonomy = ch_versions_dada_taxonomy.mix(DADA2_TAXONOMY.out.versions)

    // Collect all DADA2_TAXONOMY.out.tsv into one file
    DADA2_TAXONOMY.out.tsv
        .collectFile(name: "${ASV_tax_name}.${val_dada_ref_taxonomy}.tsv", newLine: false, cache: true, keepHeader: true, skip: 1, sort: true)
        .set { ch_dada2_taxonomy_tsv }
    ch_dada2_taxonomy_tsv.subscribe{ file(it).copyTo("${params.outdir}/dada2") }

    if (params.cut_its != "none") {
        FORMAT_TAXRESULTS_STD ( ch_dada2_taxonomy_tsv, ch_full_fasta, "ASV_tax.${val_dada_ref_taxonomy}.tsv" )
        ch_versions_dada_taxonomy = ch_versions_dada_taxonomy.mix( FORMAT_TAXRESULTS_STD.out.versions.ifEmpty(null) )
    }

    //DADA2 addSpecies
    if (!params.skip_dada_addspecies) {
        DADA2_ADDSPECIES ( DADA2_TAXONOMY.out.rds, ch_addspecies, taxlevels )

        // collect all DADA2_ADDSPECIES.out.tsv into one file
        DADA2_ADDSPECIES.out.tsv
            .collectFile(name: ASV_tax_name+"_species.${val_dada_ref_taxonomy}.tsv", newLine: false, cache: true, keepHeader: true, skip: 1, sort: true)
            .set { ch_dada2_addspecies_tsv }
        ch_dada2_addspecies_tsv.subscribe{ file(it).copyTo("${params.outdir}/dada2") }

        if (params.cut_its == "none") {
            ch_dada2_tax1 = ch_dada2_addspecies_tsv
        } else {
            FORMAT_TAXRESULTS_ADDSP ( ch_dada2_addspecies_tsv, ch_full_fasta, "ASV_tax_species.${val_dada_ref_taxonomy}.tsv" )
            ch_dada2_tax1 = FORMAT_TAXRESULTS_ADDSP.out.tsv
        }
    //no DADA2 addSpecies, use results from assignTaxonomy:
    } else {
        if (params.cut_its == "none") {
            ch_dada2_tax1 = ch_dada2_taxonomy_tsv
        } else {
            ch_dada2_tax1 = FORMAT_TAXRESULTS_STD.out.tsv
        }
    }

    //if addsh set: add SH assignments
    if ( params.addsh ) {
        //set file name prefix for SH assignments
        if (!params.skip_dada_addspecies) {
            ASV_SH_name = "ASV_tax_species_SH"
        } else {
            ASV_SH_name = "ASV_tax_SH"
        }
        //find SHs
        ch_fasta
            .map {
                fasta ->
                    def meta = [:]
                    meta.id = ASV_tax_name + ".vsearch"
                    [ meta, fasta ] }
            .set { ch_fasta_map }
        VSEARCH_USEARCHGLOBAL( ch_fasta_map, ch_assigntax, vsearch_cutoff, 'blast6out', "" )
        ch_versions_dada_taxonomy = ch_versions_dada_taxonomy.mix(VSEARCH_USEARCHGLOBAL.out.versions.ifEmpty(null))
        ASSIGNSH( ch_dada2_tax1, ch_shinfo.collect(), VSEARCH_USEARCHGLOBAL.out.txt, ASV_SH_name + ".${val_dada_ref_taxonomy}.tsv")
        ch_versions_dada_taxonomy = ch_versions_dada_taxonomy.mix(ASSIGNSH.out.versions.ifEmpty(null))
        ch_dada2_tax = ASSIGNSH.out.tsv
    } else {
        ch_dada2_tax = ch_dada2_tax1
    }

    emit:
    cut_tax  = params.cut_dada_ref_taxonomy ? CUTADAPT_TAXONOMY.out.log : [[],[]]
    tax      = ch_dada2_tax
    versions = ch_versions_dada_taxonomy
}
