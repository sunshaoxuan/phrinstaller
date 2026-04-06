import openpyxl
excel_path = "c:\\workspace\\PHRInstaller\\docs\\環境構築手順書_ONPREMISE.xlsx"
wb = openpyxl.load_workbook(excel_path, read_only=True)
print(wb.sheetnames)
