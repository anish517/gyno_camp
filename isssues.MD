In Clinical Intake, the marital status classification is: Married has Husband name; Unmarried has Father’s/Guardian’s name; Widow has Late husband/Father name; and Divorced has Father/Guardian’s name. Relation has Father, Mother, Guardian and Other in a dropdown. But on the blank form it has Relative name, Relative Surname, and Relation (Surname and Relation) in a checkbox with Husband and Father. How would it detect this?
Similarly, in the OCR form, marital status (Married, Unmarried, Widow, Divorced) is a dropdown which has the same field, Husband | Father name. How would it detect this based on the blank form?



Level of treatment is not detected when scanned.
Another issue is in diagnosis. When I scan, it does detect diagnosis, but not all of it.
Another issue is in Prescription Dispensed in the OCR form. Why does it have + Ring Pessary 65mm + Ring Pessary 70mm + Paracetamol 500mg + Iron + Folic acid in Prescriptions Dispensed? It detected an additional Ring Pessary 70mm, since it already has Pessary Fitting and Insertion, which it detects correctly. I selected Ring with (overwritten) 10mm   

but it detected 70mm, since I only have fixed pessary sizes 55mm, 60mm, 65mm, 70mm, 75mm, 80mm, 85mm. What if I write something other than this?

Another issue: POP stage is not detected.

Another issue: Surgical referral and Follow-up are not detected. There is only Referral Hospital Destination, which has None and Local Government, and Follow-up Destination, which has Camp, Follow-up Day and Local Government.

Another issue: Examining/Attending Doctor. It does detect it but does not select it on the OCR form. Similarly for Attending Nurse.




In the blank form, Province is filled automatically.
I tested by filling the form.
In the OCR form, in Obstetric History, it has Complaints Duration and Chief Clinical Complaints, which are not detected.
Clinical Notes/Intake is not in the UI in the OCR form.
In Clinical Intake there is Secondary Contact, but in the blank form there is only Contact Person, so make it Contact Person.



Another issue is in Clinical Intake and the OCR form: Outtake date, Treatment date, Conclusion date and Lab test date. In the UI there is no such date to be written, but in the blank form it has the date.



It does not detect vulva examination and uterus examination.