#!/bin/sh

# Reformat the GloSED FASTA + taxonomy table into DADA2 assignTaxonomy and
# addSpecies reference files.

set -eu

extract_zip() {
    zipfile="$1"

    if command -v unzip >/dev/null 2>&1; then
        unzip -p "$zipfile"
    elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xOf "$zipfile"
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$zipfile" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    member = archive.namelist()[0]
    with archive.open(member) as handle:
        sys.stdout.buffer.write(handle.read())
PY
    elif command -v python >/dev/null 2>&1; then
        python - "$zipfile" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    member = archive.namelist()[0]
    with archive.open(member) as handle:
        sys.stdout.buffer.write(handle.read())
PY
    else
        echo "Could not find a tool to extract $zipfile" >&2
        exit 1
    fi
}

set -- *OTU_sequences.fasta.gz*
fasta_gz="$1"
set -- *Taxonomy.tsv.zip*
taxonomy_zip="$1"

gzip -dc "$fasta_gz" | awk '
    /^>/ {
        if (sequence != "") {
            print id "\t" sequence
        }
        id = substr($0, 2)
        sequence = ""
        next
    }
    {
        sequence = sequence $0
    }
    END {
        if (id != "") {
            print id "\t" sequence
        }
    }
' | LC_ALL=C sort -t "$(printf '\t')" -k1,1 > glosed.seqs.tsv

extract_zip "$taxonomy_zip" | awk '
    BEGIN {
        FS = OFS = "\t"
    }
    function clean(value,    cleaned) {
        cleaned = value
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", cleaned)
        if (cleaned == ".") {
            cleaned = ""
        }
        gsub(/[[:space:]]+/, "_", cleaned)
        return cleaned
    }
    NR == 1 {
        next
    }
    {
        kingdom = clean($8)
        phylum = clean($9)
        class_name = clean($10)
        order = clean($11)
        family = clean($12)
        genus = clean($13)
        species = clean($14)
        sh05 = clean($20)

        if (species == "") {
            species = sh05
        }
        if (genus == "") {
            species = ""
        }
        if (kingdom == "") {
            kingdom = "Unclassified"
        }

        taxonomy = kingdom ";" phylum ";" class_name ";" order ";" family ";" genus ";" species
        print $1, taxonomy > "glosed.assign.tsv"

        if (genus != "" && species != "") {
            print $1, genus " " species > "glosed.addspecies.tsv"
        }
    }
'

join -t "$(printf '\t')" glosed.assign.tsv glosed.seqs.tsv | awk '
    BEGIN {
        FS = OFS = "\t"
    }
    {
        print ">" $2 "\n" $3
    }
' > assignTaxonomy.fna

if [ -s glosed.addspecies.tsv ]; then
    join -t "$(printf '\t')" glosed.addspecies.tsv glosed.seqs.tsv | awk '
        BEGIN {
            FS = OFS = "\t"
        }
        {
            print ">" $2 "\n" $3
        }
    ' > addSpecies.fna
else
    : > addSpecies.fna
fi