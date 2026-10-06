# Sources

Every external document a source header in `src/` or `include/` cites, and
where that document lives.

## Why this register records no filesystem path

A path is true on one machine. A reader on any other machine reaches a
citation and cannot follow it, and the citation looks like a working
reference the whole time.

So a source header cites a document by **title and revision** and never by a
path, and this file states the document's identity — publisher, designation,
and where a copy is checked against — rather than a location on somebody's
disk. Nothing checks either half except this file and a reader.

**Identity is stated as a hash where a hash is known.** A title and a
revision name an edition. A hash names the copy a measurement was taken
against, which is the thing a later reader actually has to reproduce.

**A REPOSITORY NAME IS NOT A PATH.** The rule above bans a location on
somebody's disk. It does not ban naming another repository of this project,
because that name is true on every machine that can clone it, which is the
property a path lacks.

The distinction is recorded because its absence did damage. This table used to
answer "where it lives" with **"Not in this repository"** for a document that
was, in fact, held in a sibling repository of this same project. Readers took
the phrase to mean the document was unavailable and parked claims as
unverifiable that a copy at the pinned hash could have settled. So where a
copy is held in a project repository, this table NAMES that repository. Where
no project repository holds it, this table says so, and the instruction stays
what it always was: obtain the document by its designation and check the hash
before using a value from it.

**Being able to reach a copy does not weaken the hash rule; it is what makes
the hash rule usable.** A reader who has a copy still checks the hash, because
the register pins an edition and a re-issued PDF under the same title is a
different document.

## The documents

| Cited in a header as | Document | Where it lives |
|---|---|---|
| "the ColdFire Family Programmer's Reference Manual", "…, Rev. 3" | *CFPRM, ColdFire® Family Programmer's Reference Manual*, Freescale Semiconductor. Vendor designation `CFPRM`. Revision 3. Title page states `Document Number: CFPRM`, `Rev. 3`. SHA-256 `c2d02191e4427c7af89862e756d759bf4de93b632a2c6e8c44602a075a1627d6`, 2,897,839 bytes. | **No repository of this project holds it.** Obtain the PDF from the vendor archive by its designation and check the hash before using a value from it. The hash was taken from a copy outside version control, so it pins the edition read but names no copy a later reader can reach. |
| "the MCF5307 User's Manual", "… (1998)" | Motorola, *MCF5307 ColdFire Integrated Microprocessor User's Manual*, `MCF5307UM/AD`, 1998. 456 pages, scanned paper. SHA-256 `86cbcc8c9caa933fe10275a975a78d914df86771df9f0bc22d03de8b1aff91fa`. | Not in THIS repository. **A copy at the pinned hash is held in the project's artifacts repository under its `datasheets/` directory.** That repository is private and holds third-party material: read it, do not copy the PDF into this one. A reader without access obtains the PDF by its designation. Either way, check the hash before using a value from it. **This row is NOT superseded by the MCF5407 row below.** The part modelled is the MCF5407, but a header that states what the two parts have in common still cites this manual, and a header that names a V3-only reading has to cite the manual that prints it. |
| "the MCF5407 User's Manual", "…, folio 2-11", "the manual's timing tables" | Motorola, *MCF5407 ColdFire Integrated Microprocessor User's Manual*, `MCF5407UM/D`, Rev. 0.1, 11/2001. 546 pages. SHA-256 `ebf7fe48b21c6f4c13aa2603dc9440b86eadcaa00fbca324a30935558c69f2cb`, 7,897,683 bytes. | Not in THIS repository. **A copy at the pinned hash is held in the project's artifacts repository under its `datasheets/` directory.** That repository is private and holds third-party material: read it, do not copy the PDF into this one. A reader without access obtains the PDF by its designation; the copy pinned here was obtained from `https://www.farnell.com/datasheets/2291337.pdf`. Either way, check the hash before using a value from it. |
| "the MCF5249 User's Manual", "… (2002)" | Motorola / Freescale, *MCF5249 ColdFire Integrated Microprocessor User's Manual*, `MCF5249UM`, Rev. 1, 05/2002. 344 pages. | Not in THIS repository. Obtain by its designation `MCF5249UM` and check the hash before using a value from it. Covers ISA_A+ architectural features, hardware divider, and eMAC extensions. |

**ColdFire condition codes differ from the 68000.** The CFPRM is the
authority for them, and a 68000 reference is not. `AGENTS.md` states the same
rule beside the clean-room rule, which is where an implementer meets it
first.

**A machine conversion of a scanned manual is not the manual.** A markdown or
OCR derivative may be used to FIND a page. The value goes into code only
after the page it names is read in the original. A scanned source carries
table errors that look completely normal on the page.


## Instruments

An instrument is not a document, and a header that cites one is recording a
measurement rather than an authority. `m68k-elf-as` and `m68k-elf-objdump`
are cited in the core headers as the thing that confirms which operand sizes
ISA_A accepts. Their pin is in `conformance/generate.py`.

## Unverified

| Claim | What would settle it |
|---|---|
| The table above is complete — every external document any header cites has a row | A registered check that extracts document-shaped citations from `src/` and `include/` and asserts each one has a row here |
| The `MCF5307UM/AD` and `MCF5407UM/D` hashes above identify the copies every manual-derived value in this tree was taken from, and each citation names the manual its value actually came from | Re-read one value per citing module against a PDF with the matching hash |
| The CFPRM revision every header means is 3 | Two headers name Rev. 3 and the rest name the manual alone; re-read one value per citing module against Rev. 3 |

## Related

- `AGENTS.md` — the clean-room rule that decides what may be taken from a
  source at all.
