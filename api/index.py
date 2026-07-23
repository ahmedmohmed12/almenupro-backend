import sys
import os

# إضافة المجلد الرئيسي لتطبيق Python كي يستطيع استيراد app.py
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import app
