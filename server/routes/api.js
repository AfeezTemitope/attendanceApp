import express from 'express';
import {
    markAttendance,
    getUsersWithAttendance,
    getAttendanceByMonth
} from '../controllers/attendanceController.js';
import {
    register,
    login,
    createUser,
    getUsers,
    updateUser,
    deleteUser
} from '../controllers/adminController.js';
import { validateUserCode } from '../controllers/userController.js';
import authAdmin from '../middleware/authAdmin.js';

const router = express.Router();

// Admin routes
router.post('/admin/register', register);
router.post('/admin/login', login);
router.post('/admin/users', authAdmin, createUser);
router.get('/admin/users', authAdmin, getUsers);
router.put('/admin/users/:id', authAdmin, updateUser);
router.delete('/admin/users/:id', authAdmin, deleteUser);

// User routes
router.post('/user/validate', validateUserCode);

// Attendance routes
router.post('/attendance', markAttendance);
router.get('/users', authAdmin, getUsersWithAttendance);
router.get('/attendance/month', authAdmin, getAttendanceByMonth);

export default router;