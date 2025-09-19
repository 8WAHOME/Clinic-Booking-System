/********************************************************************************
 File: clinic_booking.sql
 Purpose: Full implementation of a Clinic Booking System schema for MySQL 8+
 Notes: - Contains tables: users, patients, doctors, staff, services, rooms,
          appointments, appointment_services, invoices, payments.
        - Includes sample data and example SELECT queries (commented).
********************************************************************************/

-- Create database and select it
CREATE DATABASE IF NOT EXISTS clinic_booking;
USE clinic_booking;

-- Ensure safe re-run: drop objects in dependency-aware order
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS invoices;
DROP TABLE IF EXISTS appointment_services;
DROP TABLE IF EXISTS appointments;
DROP TABLE IF EXISTS services;
DROP TABLE IF EXISTS rooms;
DROP TABLE IF EXISTS doctors;
DROP TABLE IF EXISTS patients;
DROP TABLE IF EXISTS staff;
DROP TABLE IF EXISTS users;

SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------------
-- users: central person table for patients, doctors, and staff
-- role differentiates types. Email is unique across users.
-- common contact fields are stored here; role-specific details are in child tables.
-- ---------------------------------------------------------------------------
CREATE TABLE users (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    role ENUM('patient','doctor','staff') NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(30),
    address VARCHAR(255),
    date_of_birth DATE,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_users_email (email),
    INDEX idx_users_role (role)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- patients: patient-specific info that extends users
-- ---------------------------------------------------------------------------
CREATE TABLE patients (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    medical_record_number VARCHAR(50) NOT NULL UNIQUE,
    emergency_contact_name VARCHAR(150),
    emergency_contact_phone VARCHAR(30),
    insurance_provider VARCHAR(150),
    insurance_number VARCHAR(100),
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_patients_user FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_patients_user (user_id),
    INDEX idx_patients_mrn (medical_record_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- doctors: doctor-specific profile; references users
-- ---------------------------------------------------------------------------
CREATE TABLE doctors (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    specialty VARCHAR(150),
    license_number VARCHAR(100) UNIQUE,
    consultation_fee DECIMAL(10,2) DEFAULT 0.00,
    bio TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_doctors_user FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_doctors_user (user_id),
    INDEX idx_doctors_specialty (specialty)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- staff: administrative or support staff
-- ---------------------------------------------------------------------------
CREATE TABLE staff (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    position VARCHAR(100),
    hired_at DATE,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_staff_user FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_staff_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- services: clinic services offered (Consultation, Vaccination, Lab test, etc.)
-- duration_minutes: expected time for scheduling.
-- price: cost at the time of service.
-- ---------------------------------------------------------------------------
CREATE TABLE services (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    duration_minutes INT UNSIGNED NOT NULL CHECK (duration_minutes > 0),
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_services_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- rooms: physical rooms or bays where appointments take place
-- ---------------------------------------------------------------------------
CREATE TABLE rooms (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    room_number VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(150),
    location VARCHAR(255),
    capacity SMALLINT UNSIGNED DEFAULT 1 CHECK (capacity > 0),
    notes TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_rooms_room_number (room_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- appointments: bookings between a patient and a doctor
-- Stores scheduled start and end, status, assigned room, and optional notes.
-- ---------------------------------------------------------------------------
CREATE TABLE appointments (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    patient_id BIGINT UNSIGNED NOT NULL,        -- patients.id
    doctor_id BIGINT UNSIGNED NOT NULL,         -- doctors.id
    room_id BIGINT UNSIGNED NULL,               -- rooms.id (nullable: teleconsult)
    scheduled_start DATETIME NOT NULL,
    scheduled_end DATETIME NOT NULL,
    status ENUM('scheduled','checked_in','in_progress','completed','cancelled','no_show') NOT NULL DEFAULT 'scheduled',
    reason VARCHAR(255),
    notes TEXT,
    created_by_staff_id BIGINT UNSIGNED NULL,   -- staff.id who created the appointment
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_appointments_patient FOREIGN KEY (patient_id) REFERENCES patients(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_appointments_doctor FOREIGN KEY (doctor_id) REFERENCES doctors(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_appointments_room FOREIGN KEY (room_id) REFERENCES rooms(id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_appointments_staff FOREIGN KEY (created_by_staff_id) REFERENCES staff(id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    INDEX idx_appointments_patient (patient_id),
    INDEX idx_appointments_doctor (doctor_id),
    INDEX idx_appointments_room (room_id),
    INDEX idx_appointments_scheduled_start (scheduled_start)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- appointment_services: join table for many-to-many relationship between
-- appointments and services. Stores price snapshot and quantity for billing.
-- ---------------------------------------------------------------------------
CREATE TABLE appointment_services (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    appointment_id BIGINT UNSIGNED NOT NULL,
    service_id BIGINT UNSIGNED NOT NULL,
    quantity SMALLINT UNSIGNED NOT NULL DEFAULT 1 CHECK (quantity > 0),
    price_at_time DECIMAL(10,2) NOT NULL CHECK (price_at_time >= 0),
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_apptsvc_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_apptsvc_service FOREIGN KEY (service_id) REFERENCES services(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    UNIQUE KEY uq_appointment_service_unique (appointment_id, service_id),
    INDEX idx_apptsvc_appointment (appointment_id),
    INDEX idx_apptsvc_service (service_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- invoices: billing for appointments (one invoice per appointment).
-- total_amount stored for quick access, must be >= 0.
-- status tracks payment state. issued_at is when invoice was created.
-- ---------------------------------------------------------------------------
CREATE TABLE invoices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    appointment_id BIGINT UNSIGNED NOT NULL UNIQUE, -- one invoice per appointment
    patient_id BIGINT UNSIGNED NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL CHECK (total_amount >= 0),
    amount_due DECIMAL(10,2) NOT NULL CHECK (amount_due >= 0),
    status ENUM('pending','partial','paid','cancelled') NOT NULL DEFAULT 'pending',
    issued_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_invoices_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_invoices_patient FOREIGN KEY (patient_id) REFERENCES patients(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_invoices_patient (patient_id),
    INDEX idx_invoices_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- payments: payments applied to invoices. Multiple payments allowed per invoice.
-- ---------------------------------------------------------------------------
CREATE TABLE payments (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    invoice_id BIGINT UNSIGNED NOT NULL,
    paid_amount DECIMAL(10,2) NOT NULL CHECK (paid_amount > 0),
    payment_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    payment_method ENUM('cash','card','insurance','mobile_money','bank_transfer','other') NOT NULL,
    reference VARCHAR(255), -- e.g., transaction id
    notes TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_payments_invoice FOREIGN KEY (invoice_id) REFERENCES invoices(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    INDEX idx_payments_invoice (invoice_id),
    INDEX idx_payments_date (payment_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Basic stored data integrity triggers (optional but helpful). We will update
-- invoice amount_due automatically when payments are inserted via trigger.
-- Note: Using triggers is optional; keep minimal logic safe.
-- ---------------------------------------------------------------------------

-- Drop triggers if they exist (for rerunnable script)
DROP TRIGGER IF EXISTS trg_after_payment_insert;
DROP TRIGGER IF EXISTS trg_after_payment_delete;

DELIMITER $$

CREATE TRIGGER trg_after_payment_insert
AFTER INSERT ON payments
FOR EACH ROW
BEGIN
    -- Decrease amount_due and update status accordingly
    UPDATE invoices
    SET amount_due = GREATEST(total_amount - (
            SELECT IFNULL(SUM(paid_amount),0) FROM payments WHERE invoice_id = invoices.id
        ), 0)
    WHERE id = NEW.invoice_id;

    UPDATE invoices
    SET status = CASE
        WHEN amount_due = 0 THEN 'paid'
        WHEN amount_due < total_amount THEN 'partial'
        ELSE 'pending'
    END
    WHERE id = NEW.invoice_id;
END$$

CREATE TRIGGER trg_after_payment_delete
AFTER DELETE ON payments
FOR EACH ROW
BEGIN
    UPDATE invoices
    SET amount_due = GREATEST(total_amount - (
            SELECT IFNULL(SUM(paid_amount),0) FROM payments WHERE invoice_id = OLD.invoice_id
        ), 0)
    WHERE id = OLD.invoice_id;

    UPDATE invoices
    SET status = CASE
        WHEN amount_due = 0 THEN 'paid'
        WHEN amount_due < total_amount THEN 'partial'
        ELSE 'pending'
    END
    WHERE id = OLD.invoice_id;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------------
-- SAMPLE DATA: Insert sample users (patients, doctors, staff), services, rooms,
-- appointments + appointment_services, invoice and payment samples.
-- ---------------------------------------------------------------------------

-- Users
INSERT INTO users (role, first_name, last_name, email, phone, address, date_of_birth)
VALUES
('patient', 'Mary', 'Achieng', 'mary.achieng@example.com', '+254711000001', 'Nakuru Rd, Nairobi', '1990-05-12'),
('patient', 'John', 'Kamau', 'john.kamau@example.com', '+254711000002', 'Kimathi St, Nairobi', '1985-11-01'),
('doctor', 'Dr. Alice', 'Mwangi', 'alice.mwangi@example.com', '+254711000010', 'Clinic Block A', '1978-02-20'),
('doctor', 'Dr. Peter', 'Otieno', 'peter.otieno@example.com', '+254711000011', 'Clinic Block B', '1980-09-15'),
('staff', 'Grace', 'Wanjiru', 'grace.wanjiru@example.com', '+254711000020', 'Admin Office', NULL);

-- Patients (link to users)
INSERT INTO patients (user_id, medical_record_number, emergency_contact_name, emergency_contact_phone, insurance_provider, insurance_number)
VALUES
(1, 'MRN-000100', 'Paul Achieng', '+254700000001', 'NHIF', 'NHIF-123456'),
(2, 'MRN-000101', 'Jane Kamau', '+254700000002', NULL, NULL);

-- Doctors (link to users)
INSERT INTO doctors (user_id, specialty, license_number, consultation_fee, bio)
VALUES
(3, 'General Medicine', 'LIC-GEN-001', 1500.00, 'Experienced GP with a focus on family medicine.'),
(4, 'Pediatrics', 'LIC-PED-002', 1800.00, 'Child health specialist.');

-- Staff (link to user)
INSERT INTO staff (user_id, position, hired_at)
VALUES
(5, 'Receptionist', '2022-01-15');

-- Services
INSERT INTO services (code, name, description, price, duration_minutes)
VALUES
('CONS', 'Consultation', 'General consultation with a clinician', 1200.00, 30),
('VACC', 'Vaccination', 'Routine vaccination service', 800.00, 15),
('BLOOD', 'Blood Test (Basic)', 'Basic blood panel', 1500.00, 20),
('XRAY', 'X-Ray', 'Chest / limb X-Ray', 2000.00, 25);

-- Rooms
INSERT INTO rooms (room_number, name, location, capacity)
VALUES
('101', 'Consult Room 1', 'Ground Floor', 1),
('102', 'Consult Room 2', 'Ground Floor', 1),
('201', 'Pediatrics Room', 'First Floor', 1);

-- Appointments (two sample appointments)
-- Appointment 1: Mary with Dr. Alice
INSERT INTO appointments (patient_id, doctor_id, room_id, scheduled_start, scheduled_end, status, reason, created_by_staff_id)
VALUES
( (SELECT id FROM patients WHERE medical_record_number='MRN-000100'),
  (SELECT id FROM doctors WHERE license_number='LIC-GEN-001'),
  (SELECT id FROM rooms WHERE room_number='101'),
  '2025-09-22 09:00:00',
  '2025-09-22 09:30:00',
  'scheduled',
  'Fever and cough',
  (SELECT id FROM staff WHERE user_id=(SELECT id FROM users WHERE email='grace.wanjiru@example.com'))
);

-- Appointment 2: John with Dr. Peter
INSERT INTO appointments (patient_id, doctor_id, room_id, scheduled_start, scheduled_end, status, reason, created_by_staff_id)
VALUES
( (SELECT id FROM patients WHERE medical_record_number='MRN-000101'),
  (SELECT id FROM doctors WHERE license_number='LIC-PED-002'),
  (SELECT id FROM rooms WHERE room_number='201'),
  '2025-09-23 11:00:00',
  '2025-09-23 11:30:00',
  'scheduled',
  'Routine check',
  (SELECT id FROM staff WHERE user_id=(SELECT id FROM users WHERE email='grace.wanjiru@example.com'))
);

-- Link services to appointments with price snapshot
INSERT INTO appointment_services (appointment_id, service_id, quantity, price_at_time)
VALUES
( (SELECT id FROM appointments WHERE scheduled_start='2025-09-22 09:00:00'),
  (SELECT id FROM services WHERE code='CONS'), 1, (SELECT price FROM services WHERE code='CONS')
),
( (SELECT id FROM appointments WHERE scheduled_start='2025-09-22 09:00:00'),
  (SELECT id FROM services WHERE code='BLOOD'), 1, (SELECT price FROM services WHERE code='BLOOD')
),
( (SELECT id FROM appointments WHERE scheduled_start='2025-09-23 11:00:00'),
  (SELECT id FROM services WHERE code='CONS'), 1, (SELECT price FROM services WHERE code='CONS')
);

-- Create invoices for the appointments (calculate totals from appointment_services)
INSERT INTO invoices (appointment_id, patient_id, total_amount, amount_due, status)
SELECT
    a.id,
    a.patient_id,
    COALESCE(SUM(asv.quantity * asv.price_at_time), 0) AS total_amount,
    COALESCE(SUM(asv.quantity * asv.price_at_time), 0) AS amount_due,
    CASE WHEN COALESCE(SUM(asv.quantity * asv.price_at_time), 0) = 0 THEN 'paid' ELSE 'pending' END
FROM appointments a
LEFT JOIN appointment_services asv ON asv.appointment_id = a.id
WHERE a.scheduled_start IN ('2025-09-22 09:00:00','2025-09-23 11:00:00')
GROUP BY a.id;

-- Insert a sample payment (partial) for appointment 1 invoice
INSERT INTO payments (invoice_id, paid_amount, payment_method, reference, notes)
VALUES
( (SELECT i.id FROM invoices i JOIN appointments a ON a.id = i.appointment_id WHERE a.scheduled_start='2025-09-22 09:00:00'),
  1000.00, 'mobile_money', 'MTK-TRX-1001', 'Partial payment received via mobile money'
);

-- After the trigger, invoice.amount_due should update accordingly.

-- ---------------------------------------------------------------------------
-- Example SELECT queries for common operations (commented).
-- These lines are comments only; remove leading comment markers to run them.
-- ---------------------------------------------------------------------------

/*
-- 1) Fetch upcoming appointments for a doctor in the next 7 days
SELECT
    a.id AS appointment_id,
    CONCAT(u.first_name, ' ', u.last_name) AS patient_name,
    p.medical_record_number,
    a.scheduled_start,
    a.scheduled_end,
    a.status,
    r.room_number
FROM appointments a
JOIN patients p ON p.id = a.patient_id
JOIN users u ON u.id = p.user_id
JOIN doctors d ON d.id = a.doctor_id
LEFT JOIN rooms r ON r.id = a.room_id
WHERE d.user_id = (SELECT id FROM users WHERE email = 'alice.mwangi@example.com')
  AND a.scheduled_start BETWEEN NOW() AND DATE_ADD(NOW(), INTERVAL 7 DAY)
ORDER BY a.scheduled_start;

-- 2) Patient payment history (payments grouped by invoice)
SELECT
    u.first_name, u.last_name, p.medical_record_number,
    i.id AS invoice_id, i.total_amount, i.amount_due, i.status, i.issued_at,
    pay.id AS payment_id, pay.paid_amount, pay.payment_method, pay.payment_date, pay.reference
FROM users u
JOIN patients p ON p.user_id = u.id
JOIN invoices i ON i.patient_id = p.id
LEFT JOIN payments pay ON pay.invoice_id = i.id
WHERE u.email = 'mary.achieng@example.com'
ORDER BY pay.payment_date DESC;

-- 3) Invoice with services breakdown for an appointment
SELECT
    i.id AS invoice_id,
    CONCAT(u.first_name, ' ', u.last_name) AS patient_name,
    a.scheduled_start,
    s.code, s.name AS service_name, asv.quantity, asv.price_at_time,
    (asv.quantity * asv.price_at_time) AS line_total
FROM invoices i
JOIN appointments a ON a.id = i.appointment_id
JOIN patients p ON p.id = i.patient_id
JOIN users u ON u.id = p.user_id
JOIN appointment_services asv ON asv.appointment_id = a.id
JOIN services s ON s.id = asv.service_id
WHERE a.scheduled_start = '2025-09-22 09:00:00'
ORDER BY asv.id;

-- 4) List available rooms for a given datetime range (simple overlap check)
SELECT *
FROM rooms r
WHERE r.id NOT IN (
    SELECT room_id FROM appointments
    WHERE room_id IS NOT NULL
      AND (scheduled_start < '2025-09-22 10:00:00' AND scheduled_end > '2025-09-22 09:00:00')
);

-- 5) Aggregate revenue by service in the last 30 days
SELECT
    s.code, s.name, SUM(asv.quantity * asv.price_at_time) AS revenue
FROM appointment_services asv
JOIN services s ON s.id = asv.service_id
JOIN appointments a ON a.id = asv.appointment_id
WHERE a.scheduled_start BETWEEN DATE_SUB(NOW(), INTERVAL 30 DAY) AND NOW()
GROUP BY s.id
ORDER BY revenue DESC;
*/

-- End of script. All tables created with InnoDB and utf8mb4. Sample data inserted.
