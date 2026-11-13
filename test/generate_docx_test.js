// test script to verify docx generation
const fs = require('fs');
const path = require('path');

function createDocxTemplateBlob() {
  const contentTypesXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>`;

  const relsXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>`;

  const docXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="32"/></w:rPr><w:t>PETUNJUK FORMAT SOAL CBT EXAMGO (.DOCX)</w:t></w:r></w:p>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:i/><w:color w:val="666666"/></w:rPr><w:t>Gunakan dokumen ini sebagai panduan penulisan soal ujian.</w:t></w:r></w:p>
    <w:p/>
    <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>1. Manakah ibukota negara Indonesia saat ini?</w:t></w:r></w:p>
    <w:p><w:r><w:t>A. Bandung</w:t></w:r></w:p>
    <w:p><w:r><w:t>B. Jakarta</w:t></w:r></w:p>
    <w:p><w:r><w:t>C. Surabaya</w:t></w:r></w:p>
    <w:p><w:r><w:t>D. Medan</w:t></w:r></w:p>
    <w:p><w:r><w:t>E. Denpasar</w:t></w:r></w:p>
    <w:p><w:r><w:rPr><w:b/><w:color w:val="008800"/></w:rPr><w:t>Kunci: B</w:t></w:r></w:p>
    <w:p><w:r><w:rPr><w:i/></w:rPr><w:t>Pembahasan: Berdasarkan undang-undang saat ini, ibukota RI adalah Jakarta.</w:t></w:r></w:p>
    <w:p/>
    <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>2. Berapakah hasil dari persamaan kuadrat x^2 - 16 = 0?</w:t></w:r></w:p>
    <w:p><w:r><w:t>A. x = 2 atau x = -2</w:t></w:r></w:p>
    <w:p><w:r><w:t>B. x = 4 atau x = -4</w:t></w:r></w:p>
    <w:p><w:r><w:t>C. x = 8 atau x = -8</w:t></w:r></w:p>
    <w:p><w:r><w:t>D. x = 16 atau x = -16</w:t></w:r></w:p>
    <w:p><w:r><w:t>E. x = 0</w:t></w:r></w:p>
    <w:p><w:r><w:rPr><w:b/><w:color w:val="008800"/></w:rPr><w:t>Kunci: B</w:t></w:r></w:p>
    <w:p><w:r><w:rPr><w:i/></w:rPr><w:t>Pembahasan: x^2 = 16 =&gt; x = ±4.</w:t></w:r></w:p>
    <w:p/>
    <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>3. Perhatikan data nilai ulangan berikut:</w:t></w:r></w:p>
    <w:tbl>
      <w:tblPr>
        <w:tblBorders>
          <w:top w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
          <w:left w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
          <w:bottom w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
          <w:right w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
          <w:insideH w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
          <w:insideV w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
        </w:tblBorders>
      </w:tblPr>
      <w:tr>
        <w:tc><w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Nilai</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Frekuensi</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:p><w:r><w:t>70 - 79</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>12</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:p><w:r><w:t>80 - 89</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>18</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:p><w:r><w:t>90 - 100</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>10</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>
    <w:p><w:r><w:t>Berapakah jumlah seluruh siswa yang mengikuti ulangan?</w:t></w:r></w:p>
    <w:p><w:r><w:t>A. 30</w:t></w:r></w:p>
    <w:p><w:r><w:t>B. 35</w:t></w:r></w:p>
    <w:p><w:r><w:t>C. 40</w:t></w:r></w:p>
    <w:p><w:r><w:t>D. 45</w:t></w:r></w:p>
    <w:p><w:r><w:t>E. 50</w:t></w:r></w:p>
    <w:p><w:r><w:rPr><w:b/><w:color w:val="008800"/></w:rPr><w:t>Kunci: C</w:t></w:r></w:p>
    <w:p><w:r><w:rPr><w:i/></w:rPr><w:t>Pembahasan: Total frekuensi = 12 + 18 + 10 = 40 siswa.</w:t></w:r></w:p>
    <w:sectPr/>
  </w:body>
</w:document>`;

  return { contentTypesXml, relsXml, docXml };
}

const res = createDocxTemplateBlob();
console.log('Docx template XML generated successfully, docXml length:', res.docXml.length);
