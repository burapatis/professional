# ครุจิต — Hugo migration (ระยะที่ 1-2: เสร็จสมบูรณ์ครบ 8 หน้า)

แปลงครบทุกหน้าจาก raw HTML เดิม เป็น Hugo layout + data file แล้ว
ทดสอบ build ผ่านด้วย `hugo v0.123.7+extended` — 8 หน้าย่อย + หน้าแรก ลิงก์ภายในทั้งหมด
ตรวจสอบแล้วว่า resolve ถูกต้องครบ ไม่มีลิงก์เสีย (ดูวิธีตรวจในส่วน "วิธีทดสอบ" ด้านล่าง)

## โครงสร้างไฟล์

```
content/            หน้าละ 1 ไฟล์ .md (front matter เท่านั้น เนื้อหาจริงอยู่ใน layouts/)
  _index.md, standards.md, ethics.md, pathway.md, professionalism.md,
  international.md, knowledge.md, about.md

data/
  standards_knowledge.yaml     มาตรฐานที่ 1: 6 ด้านความรู้ (ข้อบังคับฉบับที่ 4 พ.ศ. 2562)
  standards_performance.yaml   มาตรฐานที่ 2: 3 ด้าน 15 ข้อย่อย (ก/ข/ค ตามกฎหมาย)
  knowledge_domains.yaml       คลังความรู้ 6 หมวด (รื้อจาก 11 หัวข้อเดิม ดูหมายเหตุในไฟล์)
  international_countries.yaml รายชื่อ 14 ประเทศ/กรอบมาตรฐาน แบ่ง 3 ภูมิภาค

layouts/
  _default/baseof.html        โครงหลักของทุกหน้า
  _default/{standards,ethics,pathway,professionalism,international,knowledge,about}.html
  index.html                  หน้าแรก
  partials/header.html            nav bar ใช้ร่วมกันทุกหน้า
  partials/footer-full.html       footer 4 คอลัมน์ (หน้าแรกเท่านั้น)
  partials/footer-simple.html     footer บรรทัดเดียว (หน้าย่อยทั้งหมด)
  partials/country-card.html      การ์ดประเทศ (ใช้ซ้ำ 14 ครั้งในหน้า international)

static/css/   base.css (ร่วมทุกหน้า) + ไฟล์ต่อหน้า (home.css, standards.css, ethics.css, ...)
static/js/site.js   JS ที่ใช้ร่วมกันทุกหน้า

.github/workflows/hugo-deploy.yml   ไฟล์ deploy ที่ใช้ในระยะที่ 3
```

## เนื้อหาที่แก้ไขให้ถูกต้องไปพร้อมกับการย้าย (ตาม Prompt for Cursor 2)

ทำไปพร้อมกับการ migrate แต่ละหน้าตามที่วางแผนไว้ (ไม่แยกเป็น 2 รอบ):

- **standards.html** — 11 ด้าน/12 ข้อ → 6 ด้าน/15 ข้อ (ก/ข/ค) พร้อมลิงก์อ้างอิงราชกิจจานุเบกษา
- **index.html** — stat, การ์ดเข็ม, การ์ดมาตรฐานสรุป แก้ตัวเลขให้ตรงกัน
- **pathway.html** — แก้ "มาตรฐานความรู้ 11 ด้าน" → 6 ด้าน (1 จุด)
- **international.html** — การ์ดประเทศไทยแก้ "11 มาตรฐาน/11 ด้านความรู้" → 6 มาตรฐาน/6 ด้าน
- **knowledge.html** — รื้อ accordion จาก 11 หัวข้อเดิม เป็น 6 หัวข้อใหม่ จับคู่ทฤษฎีเดิม
  (Piaget, Vygotsky, Dweck, TPACK, Backward Design, Action Research ฯลฯ) เข้าหมวดใหม่ที่ใกล้เคียงที่สุด
  ไม่มีเนื้อหาใดถูกทิ้ง — ดูคอมเมนต์ใน `data/knowledge_domains.yaml` สำหรับตาราง mapping เต็ม
- **ethics.html** — ไม่แก้เนื้อหา (จรรยาบรรณไม่เปลี่ยนตามกฎหมาย) ย้ายแค่โครงสร้าง

⚠️ **raw HTML ตัวจริงบน GitHub** (`pathway.html`, `international.html`, `knowledge.html`) ยังเป็นเลขเก่าอยู่
(ต่างจาก `standards.html`/`index.html` ที่แพตช์ไปแล้วก่อนหน้านี้) เพราะรอบนี้แก้ตรงในไฟล์ Hugo ไปพร้อมกับการ
migrate เลย ยังไม่ได้แพตช์ raw HTML คู่กัน — ถ้าต้องการให้แพตช์ raw ไฟล์เหล่านี้ด้วยเพื่อให้เว็บจริงถูกต้อง
ระหว่างรอ cutover บอกได้เลย (knowledge.html ใช้เวลานานสุดเพราะต้องรื้อ accordion ทั้งหมด)

## วิธีทดสอบในเครื่อง

```bash
hugo server
```
เปิด http://localhost:1313 แล้วลองคลิกลิงก์ในแต่ละหน้า / กดเปิด accordion ในหน้าคลังความรู้

## งานที่เหลือ (ระยะที่ 3-4)

ทุกหน้า migrate ครบแล้ว ขั้นต่อไปคือ:
1. ตั้งค่า GitHub Actions (ไฟล์ `hugo-deploy.yml` พร้อมใช้แล้ว)
2. เปลี่ยน Settings → Pages → Source เป็น "GitHub Actions"
3. Cutover เข้า `main`

