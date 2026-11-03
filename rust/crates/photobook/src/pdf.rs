use std::hash::{DefaultHasher, Hasher};

use moxcms::{ColorProfile, ProfileText};

use crate::{Error, cmyk::CmykJpegEncoder};

const HEADER: &[u8] = b"%PDF-1.6\n%\xE2\xE3\xCF\xD3\n";
const PRODUCER: &str = "Ente Photobook";
const POINTS_PER_MM: f64 = 72.0 / 25.4;
const CATALOG: usize = 1;
const PAGES: usize = 2;
const OUTPUT_PROFILE: usize = 3;
const OUTPUT_INTENT: usize = 4;
const INFO: usize = 5;
const METADATA: usize = 6;
const MAX_XREF_OFFSET: u64 = 9_999_999_999;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PageSize {
    pub width_mm: f64,
    pub height_mm: f64,
}

pub struct PdfX4Writer {
    encoder: CmykJpegEncoder,
    page_width: String,
    page_height: String,
    created_at: i64,
    buffer: Vec<u8>,
    written: u64,
    offsets: Vec<u64>,
    pages: Vec<usize>,
    content_hash: DefaultHasher,
}

impl PdfX4Writer {
    pub fn new(
        output_profile: &[u8],
        output_condition_identifier: &str,
        page_size: PageSize,
        created_at_unix_seconds: i64,
    ) -> Result<Self, Error> {
        let PageSize {
            width_mm,
            height_mm,
        } = page_size;
        if !(width_mm.is_finite() && height_mm.is_finite() && width_mm > 0.0 && height_mm > 0.0) {
            return Err(Error::InvalidPageSize);
        }
        let profile =
            ColorProfile::new_from_slice(output_profile).map_err(Error::InvalidProfile)?;
        let mut writer = Self {
            encoder: CmykJpegEncoder::new(&profile)?,
            page_width: format!("{:.5}", width_mm * POINTS_PER_MM),
            page_height: format!("{:.5}", height_mm * POINTS_PER_MM),
            created_at: created_at_unix_seconds,
            buffer: HEADER.to_vec(),
            written: 0,
            offsets: vec![0; METADATA + 1],
            pages: Vec::new(),
            content_hash: DefaultHasher::new(),
        };

        writer.stream_object(
            OUTPUT_PROFILE,
            "/N 4 /Alternate /DeviceCMYK",
            output_profile,
        );
        let identifier = text_string(output_condition_identifier);
        let condition = text_string(
            &description(&profile).unwrap_or_else(|| output_condition_identifier.to_owned()),
        );
        writer.object(
            OUTPUT_INTENT,
            &format!(
                "<< /Type /OutputIntent /S /GTS_PDFX /OutputConditionIdentifier {identifier} \
                 /OutputCondition {condition} /RegistryName (http://www.color.org) \
                 /Info {condition} /DestOutputProfile {OUTPUT_PROFILE} 0 R >>"
            ),
        );
        Ok(writer)
    }

    pub fn add_page(
        &mut self,
        srgb_rgba: Vec<u8>,
        width: u16,
        height: u16,
    ) -> Result<Vec<u8>, Error> {
        let jpeg = self.encoder.encode(srgb_rgba, width, height)?;
        self.content_hash.write(&jpeg);

        let page = self.offsets.len();
        let (image, content) = (page + 1, page + 2);
        let page_box = format!("[0 0 {} {}]", self.page_width, self.page_height);
        let placement = format!(
            "q\n{} 0 0 {} 0 0 cm\n/Im0 Do\nQ\n",
            self.page_width, self.page_height
        );
        self.object(
            page,
            &format!(
                "<< /Type /Page /Parent {PAGES} 0 R /MediaBox {page_box} /TrimBox {page_box} \
                 /BleedBox {page_box} /Resources << /ProcSet [/PDF /ImageC] \
                 /XObject << /Im0 {image} 0 R >> >> /Contents {content} 0 R >>"
            ),
        );
        self.stream_object(
            image,
            &format!(
                "/Type /XObject /Subtype /Image /Width {width} /Height {height} \
                 /ColorSpace /DeviceCMYK /BitsPerComponent 8 /Filter /DCTDecode \
                 /Decode [1 0 1 0 1 0 1 0] /Interpolate false"
            ),
            &jpeg,
        );
        self.stream_object(content, "", placement.as_bytes());
        self.pages.push(page);
        Ok(self.flush())
    }

    pub fn finish(mut self) -> Result<Vec<u8>, Error> {
        if self.pages.is_empty() {
            return Err(Error::NoPages);
        }
        let kids = self
            .pages
            .iter()
            .map(|page| format!("{page} 0 R"))
            .collect::<Vec<_>>()
            .join(" ");
        self.object(
            PAGES,
            &format!(
                "<< /Type /Pages /Kids [{kids}] /Count {} >>",
                self.pages.len()
            ),
        );

        let [year, month, day, hour, minute, second] = utc(self.created_at);
        let pdf_date =
            format!("(D:{year:04}{month:02}{day:02}{hour:02}{minute:02}{second:02}+00'00')");
        let xmp_date = format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}Z");
        let producer = text_string(PRODUCER);
        self.object(
            INFO,
            &format!(
                "<< /Title {producer} /Creator {producer} /Producer {producer} \
                 /CreationDate {pdf_date} /ModDate {pdf_date} /Trapped /False \
                 /GTS_PDFXVersion (PDF/X-4) >>"
            ),
        );

        let id = self.document_id();
        let hex = id
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        let uuid = format!(
            "{}-{}-{}-{}-{}",
            &hex[..8],
            &hex[8..12],
            &hex[12..16],
            &hex[16..20],
            &hex[20..]
        );
        self.stream_object(
            METADATA,
            "/Type /Metadata /Subtype /XML",
            xmp(&xmp_date, &uuid).as_bytes(),
        );
        self.object(
            CATALOG,
            &format!(
                "<< /Type /Catalog /Pages {PAGES} 0 R /OutputIntents [{OUTPUT_INTENT} 0 R] \
                 /Metadata {METADATA} 0 R /ViewerPreferences << /DisplayDocTitle true >> >>"
            ),
        );

        let xref = self.position();
        if xref > MAX_XREF_OFFSET {
            return Err(Error::TooLarge);
        }
        let size = self.offsets.len();
        let mut table = format!("xref\n0 {size}\n0000000000 65535 f \n");
        for offset in &self.offsets[1..] {
            table.push_str(&format!("{offset:010} 00000 n \n"));
        }
        table.push_str(&format!(
            "trailer\n<< /Size {size} /Root {CATALOG} 0 R /Info {INFO} 0 R \
             /ID [<{hex}> <{hex}>] >>\nstartxref\n{xref}\n%%EOF\n"
        ));
        self.buffer.extend_from_slice(table.as_bytes());
        Ok(self.flush())
    }

    fn object(&mut self, id: usize, body: &str) {
        self.begin_object(id);
        self.buffer
            .extend_from_slice(format!("{body}\nendobj\n").as_bytes());
    }

    fn stream_object(&mut self, id: usize, dict: &str, data: &[u8]) {
        self.begin_object(id);
        self.buffer
            .extend_from_slice(format!("<< {dict} /Length {} >>\nstream\n", data.len()).as_bytes());
        self.buffer.extend_from_slice(data);
        self.buffer.extend_from_slice(b"\nendstream\nendobj\n");
    }

    fn begin_object(&mut self, id: usize) {
        if self.offsets.len() <= id {
            self.offsets.resize(id + 1, 0);
        }
        self.offsets[id] = self.position();
        self.buffer
            .extend_from_slice(format!("{id} 0 obj\n").as_bytes());
    }

    fn position(&self) -> u64 {
        self.written + self.buffer.len() as u64
    }

    fn flush(&mut self) -> Vec<u8> {
        let chunk = std::mem::take(&mut self.buffer);
        self.written += chunk.len() as u64;
        chunk
    }

    fn document_id(&self) -> [u8; 16] {
        let mut hasher = self.content_hash.clone();
        hasher.write_i64(self.created_at);
        let high = hasher.finish();
        hasher.write_u64(high);
        let low = hasher.finish();
        let mut id = [0; 16];
        id[..8].copy_from_slice(&high.to_be_bytes());
        id[8..].copy_from_slice(&low.to_be_bytes());
        id[6] = (id[6] & 0x0F) | 0x40;
        id[8] = (id[8] & 0x3F) | 0x80;
        id
    }
}

fn description(profile: &ColorProfile) -> Option<String> {
    let text = match profile.description.as_ref()? {
        ProfileText::PlainString(text) => text,
        ProfileText::Localizable(texts) => &texts.first()?.value,
        ProfileText::Description(description) => &description.ascii_string,
    };
    let text = text.trim_matches(|c: char| c == '\0' || c.is_whitespace());
    (!text.is_empty()).then(|| text.to_owned())
}

fn text_string(text: &str) -> String {
    if text.chars().all(|c| c == ' ' || c.is_ascii_graphic()) {
        let escaped = text
            .replace('\\', "\\\\")
            .replace('(', "\\(")
            .replace(')', "\\)");
        format!("({escaped})")
    } else {
        let utf16 = std::iter::once(0xFEFF)
            .chain(text.encode_utf16())
            .map(|unit| format!("{unit:04X}"))
            .collect::<String>();
        format!("<{utf16}>")
    }
}

fn utc(unix_seconds: i64) -> [i64; 6] {
    let days = unix_seconds.div_euclid(86_400);
    let seconds = unix_seconds.rem_euclid(86_400);
    let shifted = days + 719_468;
    let era = shifted.div_euclid(146_097);
    let day_of_era = shifted.rem_euclid(146_097);
    let year_of_era =
        (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_from_march = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_from_march + 2) / 5 + 1;
    let month = if month_from_march < 10 {
        month_from_march + 3
    } else {
        month_from_march - 9
    };
    let year = era * 400 + year_of_era + i64::from(month <= 2);
    [
        year,
        month,
        day,
        seconds / 3_600,
        seconds % 3_600 / 60,
        seconds % 60,
    ]
}

fn xmp(date: &str, uuid: &str) -> String {
    format!(
        r#"<?xpacket begin="{bom}" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="{PRODUCER}">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about="" xmlns:pdfxid="http://www.npes.org/pdfx/ns/id/">
      <pdfxid:GTS_PDFXVersion>PDF/X-4</pdfxid:GTS_PDFXVersion>
    </rdf:Description>
    <rdf:Description rdf:about="" xmlns:pdf="http://ns.adobe.com/pdf/1.3/">
      <pdf:Producer>{PRODUCER}</pdf:Producer>
      <pdf:Trapped>False</pdf:Trapped>
    </rdf:Description>
    <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/">
      <xmp:CreatorTool>{PRODUCER}</xmp:CreatorTool>
      <xmp:CreateDate>{date}</xmp:CreateDate>
      <xmp:ModifyDate>{date}</xmp:ModifyDate>
      <xmp:MetadataDate>{date}</xmp:MetadataDate>
    </rdf:Description>
    <rdf:Description rdf:about="" xmlns:xmpMM="http://ns.adobe.com/xap/1.0/mm/">
      <xmpMM:DocumentID>uuid:{uuid}</xmpMM:DocumentID>
      <xmpMM:InstanceID>uuid:{uuid}</xmpMM:InstanceID>
      <xmpMM:RenditionClass>default</xmpMM:RenditionClass>
      <xmpMM:VersionID>1</xmpMM:VersionID>
    </rdf:Description>
    <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/">
      <dc:format>application/pdf</dc:format>
      <dc:title>
        <rdf:Alt>
          <rdf:li xml:lang="x-default">{PRODUCER}</rdf:li>
        </rdf:Alt>
      </dc:title>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>
<?xpacket end="w"?>"#,
        bom = '\u{FEFF}',
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_profile::key_only_profile;

    const A5: PageSize = PageSize {
        width_mm: 148.0,
        height_mm: 210.0,
    };

    fn writer() -> PdfX4Writer {
        PdfX4Writer::new(&key_only_profile(), "FOGRA39", A5, 1_000_000_000).unwrap()
    }

    fn pdf_with_pages(sizes: &[(u16, u16)]) -> Vec<u8> {
        let mut writer = writer();
        let mut pdf = Vec::new();
        for &(width, height) in sizes {
            let pixels = vec![200; usize::from(width) * usize::from(height) * 4];
            pdf.extend(writer.add_page(pixels, width, height).unwrap());
        }
        pdf.extend(writer.finish().unwrap());
        pdf
    }

    fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
        haystack.windows(needle.len()).position(|w| w == needle)
    }

    fn trailer(pdf: &[u8]) -> &str {
        let at = find(pdf, b"trailer\n").unwrap();
        std::str::from_utf8(&pdf[at..]).unwrap()
    }

    #[test]
    fn indexes_every_object_in_the_xref_table() {
        let pdf = pdf_with_pages(&[(3, 2), (2, 2)]);
        assert!(pdf.starts_with(HEADER));
        assert!(pdf.ends_with(b"%%EOF\n"));

        let startxref = trailer(&pdf).lines().rev().nth(1).unwrap();
        let xref: usize = startxref.parse().unwrap();
        let table = std::str::from_utf8(&pdf[xref..]).unwrap();
        let mut lines = table.lines();
        assert_eq!(lines.next(), Some("xref"));
        assert_eq!(lines.next(), Some("0 13"));
        assert_eq!(lines.next(), Some("0000000000 65535 f "));
        for id in 1..13 {
            let offset: usize = lines.next().unwrap()[..10].parse().unwrap();
            assert!(pdf[offset..].starts_with(format!("{id} 0 obj\n").as_bytes()));
        }
        assert!(trailer(&pdf).contains("/Size 13 /Root 1 0 R /Info 5 0 R"));
    }

    #[test]
    fn describes_pages_profile_and_metadata() {
        let pdf = pdf_with_pages(&[(3, 2), (2, 2)]);
        for needle in [
            "/Type /Pages /Kids [7 0 R 10 0 R] /Count 2",
            "/MediaBox [0 0 419.52756 595.27559] /TrimBox [0 0 419.52756 595.27559]",
            "/Width 3 /Height 2 /ColorSpace /DeviceCMYK",
            "/Width 2 /Height 2 /ColorSpace /DeviceCMYK",
            "q\n419.52756 0 0 595.27559 0 0 cm\n/Im0 Do\nQ\n",
            "/S /GTS_PDFX /OutputConditionIdentifier (FOGRA39) /OutputCondition (FOGRA39)",
            "/DestOutputProfile 3 0 R",
            "/CreationDate (D:20010909014640+00'00')",
            "/GTS_PDFXVersion (PDF/X-4)",
            "<xmp:CreateDate>2001-09-09T01:46:40Z</xmp:CreateDate>",
        ] {
            assert!(find(&pdf, needle.as_bytes()).is_some(), "{needle}");
        }
        let profile = key_only_profile();
        let embedded = [
            format!(
                "3 0 obj\n<< /N 4 /Alternate /DeviceCMYK /Length {} >>\nstream\n",
                profile.len()
            )
            .as_bytes(),
            &profile,
        ]
        .concat();
        assert!(find(&pdf, &embedded).is_some());
    }

    #[test]
    fn returns_the_file_in_page_chunks() {
        let mut writer = writer();
        let first = writer.add_page(vec![0; 16], 2, 2).unwrap();
        let second = writer.add_page(vec![0; 16], 2, 2).unwrap();
        let last = writer.finish().unwrap();
        assert!(first.starts_with(HEADER));
        assert!(find(&first, b"/DestOutputProfile").is_some());
        assert!(second.starts_with(b"10 0 obj\n"));
        assert!(find(&second, b"/DestOutputProfile").is_none());
        assert!(last.starts_with(b"2 0 obj\n"));
    }

    #[test]
    fn keeps_offsets_exact_past_four_gibibytes() {
        let mut writer = writer();
        writer.add_page(vec![0; 16], 2, 2).unwrap();
        writer.written += 1 << 32;
        let page_start = writer.written;
        let page = writer.add_page(vec![0; 16], 2, 2).unwrap();
        assert_eq!(writer.offsets[10], page_start);

        let last = writer.finish().unwrap();
        let table_start = find(&last, b"xref\n").unwrap();
        let table = std::str::from_utf8(&last[table_start..]).unwrap();
        let xref = page_start + page.len() as u64 + table_start as u64;
        assert!(xref > u64::from(u32::MAX));
        assert!(table.contains(&format!("{page_start:010} 00000 n \n")));
        assert!(table.ends_with(&format!("startxref\n{xref}\n%%EOF\n")));
    }

    #[test]
    fn rejects_files_too_large_for_the_xref_table() {
        let mut writer = writer();
        writer.add_page(vec![0; 16], 2, 2).unwrap();
        writer.written = MAX_XREF_OFFSET;
        assert!(matches!(writer.finish(), Err(Error::TooLarge)));
    }

    #[test]
    fn derives_the_document_id_from_the_content() {
        let id = |pdf: &[u8]| {
            let trailer = trailer(pdf);
            let start = trailer.find("/ID [<").unwrap() + 6;
            trailer[start..start + 32].to_owned()
        };
        let one = id(&pdf_with_pages(&[(2, 2)]));
        assert_eq!(one, id(&pdf_with_pages(&[(2, 2)])));
        assert_ne!(one, id(&pdf_with_pages(&[(3, 2)])));
        assert_eq!(&one[12..13], "4");
    }

    #[test]
    fn converts_timestamps_to_utc() {
        assert_eq!(utc(0), [1970, 1, 1, 0, 0, 0]);
        assert_eq!(utc(951_782_400), [2000, 2, 29, 0, 0, 0]);
        assert_eq!(utc(1_000_000_000), [2001, 9, 9, 1, 46, 40]);
        assert_eq!(utc(-1), [1969, 12, 31, 23, 59, 59]);
    }

    #[test]
    fn encodes_text_strings() {
        assert_eq!(text_string("A (b) \\"), "(A \\(b\\) \\\\)");
        assert_eq!(text_string("Café"), "<FEFF00430061006600E9>");
    }

    #[test]
    fn rejects_invalid_input() {
        assert!(matches!(writer().finish(), Err(Error::NoPages)));
        for (width_mm, height_mm) in [(0.0, 210.0), (148.0, -1.0), (f64::NAN, 210.0)] {
            let size = PageSize {
                width_mm,
                height_mm,
            };
            assert!(matches!(
                PdfX4Writer::new(&key_only_profile(), "FOGRA39", size, 0),
                Err(Error::InvalidPageSize)
            ));
        }
        assert!(matches!(
            PdfX4Writer::new(b"not a profile", "FOGRA39", A5, 0),
            Err(Error::InvalidProfile(_))
        ));
        let srgb = ColorProfile::new_srgb().encode().unwrap();
        assert!(matches!(
            PdfX4Writer::new(&srgb, "FOGRA39", A5, 0),
            Err(Error::NotCmykProfile)
        ));
    }
}
