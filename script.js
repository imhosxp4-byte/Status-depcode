const data = [
  {
    id: "visit_1",
    title: "เยี่ยมชมโครงการ A",
    date: "2026-05-15",
    location: "กรุงเทพมหานคร",
    description: "ตรวจสอบความคืบหน้าและประชุมทีมงานโครงการ A"
  },
  {
    id: "visit_2",
    title: "เยี่ยมชมโครงการ B",
    date: "2026-05-22",
    location: "เชียงใหม่",
    description: "สำรวจพื้นที่และวางแผนการดำเนินงาน"
  },
  {
    id: "visit_3",
    title: "เยี่ยมชมโครงการ C",
    date: "2026-05-28",
    location: "ชลบุรี",
    description: "ประชุมลูกค้าและสรุปงานก่อนส่งมอบ"
  }
];

const selectElement = document.getElementById("dataSelect");
const resultElement = document.getElementById("result");

function renderOptions() {
  data.forEach(item => {
    const option = document.createElement("option");
    option.value = item.id;
    option.textContent = item.title;
    selectElement.appendChild(option);
  });
}

function renderResult(item) {
  if (!item) {
    resultElement.innerHTML = "<p>ยังไม่มีข้อมูลที่ถูกเลือก</p>";
    return;
  }

  resultElement.innerHTML = `
    <h3>${item.title}</h3>
    <ul>
      <li><strong>วันที่:</strong> ${item.date}</li>
      <li><strong>สถานที่:</strong> ${item.location}</li>
      <li><strong>รายละเอียด:</strong> ${item.description}</li>
    </ul>
  `;
}

selectElement.addEventListener("change", event => {
  const selectedId = event.target.value;
  const selectedItem = data.find(item => item.id === selectedId);
  renderResult(selectedItem);
});

renderOptions();
renderResult(null);
