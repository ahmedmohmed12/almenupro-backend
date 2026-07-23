import json
import os

from dotenv import load_dotenv
from fastapi import FastAPI, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from google import genai
from google.genai import types
from pydantic import BaseModel

load_dotenv()

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# تهيئة عميل Gemini الجديد باستخدام المفتاح الموجود في البيئة
# تأكد من وجود مفتاح GEMINI_API_KEY في ملف .env الخاص بك
client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))


class OrderPayload(BaseModel):
    order_id: str
    customer_name: str
    customer_phone: str
    driver_name: str
    driver_phone: str


# 1. مسار استقبال الصورة وتحليلها عبر Gemini
@app.post("/analyze-image")
async def analyze_image(file: UploadFile = File(...)):
    try:
        image_bytes = await file.read()

        # إعداد الطلب لـ Gemini لقراءة الصورة واستخراج البيانات المحددة
        prompt = """
        قم بتحليل صورة الفاتورة أو الطلب المرفقة واستخرج البيانات التالية بدقة:
        1. اسم العميل (customer_name)
        2. رقم هاتف العميل (customer_phone) - تأكد من استخراجه كأرقام فقط بدون مسافات.
        3. رقم الطلب (order_id)

        يجب أن تعيد النتيجة بصيغة JSON فقط دون أي نصوص إضافية خارج أقواس الـ JSON، وبالمفاتيح المحددة أعلاه.
        """

        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=[
                types.Part.from_bytes(
                    data=image_bytes,
                    mime_type=file.content_type,
                ),
                prompt,
            ],
            # إجبار النموذج على إرجاع النتيجة كـ JSON منظم
            config=types.GenerateContentConfig(response_mime_type="application/json"),
        )

        # تحويل النص المستلم إلى كائن JSON وإعادته لصفحة الويب
        extracted_data = json.loads(response.text)
        return {"status": "success", "data": extracted_data}

    except Exception as e:
        return {"status": "error", "message": str(e)}


# 2. مسار حفظ الطلب وتكليف السائق (يمكنك ربطه بـ Vocode لاحقاً)
@app.post("/save-and-dispatch")
def save_and_dispatch(data: OrderPayload):
    # هنا يتم استقبال البيانات النهائية بعد مراجعتها وحفظها
    print(f"تم حفظ الطلب بنجاح: {data.order_id}")
    return {"status": "success", "message": "Order processed successfully."}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8000)
