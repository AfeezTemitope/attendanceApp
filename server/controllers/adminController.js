import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import Admin from '../models/Admin.js';
import User from '../models/User.js';
import Attendance from '../models/Attendance.js';

const generateToken = (id) => {
    return jwt.sign({ id }, process.env.JWT_SECRET_ADMIN, { expiresIn: '1h' });
};

export const register = async (req, res) => {
    const { username, email, password, companyName } = req.body;
    if (!username || !email || !password || !companyName) {
        return res.status(400).json({ success: false, message: 'All fields are required' });
    }

    try {
        const existingAdmin = await Admin.findOne({ $or: [{ username }, { email }] });
        if (existingAdmin) {
            return res.status(400).json({ success: false, message: 'Username or email already exists' });
        }

        const hashedPassword = await bcrypt.hash(password, 10);
        const admin = await Admin.create({ username, email, password: hashedPassword, companyName });
        const token = generateToken(admin._id);

        res.status(201).json({
            success: true,
            data: { token, companyName },
            message: `Company ${companyName} registered successfully`,
        });
    } catch (error) {
        res.status(500).json({ success: false, message: 'Server error', error: error.message });
    }
};

export const login = async (req, res) => {
    const { username, password } = req.body;
    if (!username || !password) {
        return res.status(400).json({ success: false, message: 'All fields are required' });
    }

    try {
        const admin = await Admin.findOne({ username });
        if (!admin || !(await bcrypt.compare(password, admin.password))) {
            return res.status(401).json({ success: false, message: 'Invalid credentials' });
        }

        const token = generateToken(admin._id);
        res.json({ success: true, data: { token, companyName: admin.companyName } });
    } catch (error) {
        res.status(500).json({ success: false, message: 'Server error', error: error.message });
    }
};

export const createUser = async (req, res) => {
    const { name, userCode } = req.body;
    const adminId = req.admin.id;

    if (!name || !userCode) {
        return res.status(400).json({ success: false, message: 'Name and user code are required' });
    }

    try {
        const existingUser = await User.findOne({ userCode });
        if (existingUser) {
            return res.status(400).json({ success: false, message: 'User code already exists' });
        }

        const user = await User.create({ name, userCode, admin: adminId });
        res.status(201).json({ success: true, data: user });
    } catch (error) {
        res.status(500).json({ success: false, message: 'Server error', error: error.message });
    }
};

export const getUsers = async (req, res) => {
    try {
        const users = await User.find({ admin: req.admin.id }).select('-admin');
        res.json({ success: true, data: users });
    } catch (error) {
        res.status(500).json({ success: false, message: 'Server error', error: error.message });
    }
};

export const updateUser = async (req, res) => {
    const { id } = req.params;
    const { name, userCode } = req.body;

    try {
        const user = await User.findOne({ _id: id, admin: req.admin.id });
        if (!user) {
            return res.status(404).json({ success: false, message: 'User not found' });
        }

        if (name) user.name = name;
        if (userCode) user.userCode = userCode;

        await user.save();
        res.json({ success: true, data: user });
    } catch (error) {
        res.status(500).json({ success: false, message: 'Server error', error: error.message });
    }
};

export const deleteUser = async (req, res) => {
    const { id } = req.params;

    try {
        const user = await User.findOneAndDelete({ _id: id, admin: req.admin.id });
        if (!user) {
            return res.status(404).json({ success: false, message: 'User not found' });
        }

        await Attendance.deleteMany({ name: user.name, admin: req.admin.id });
        res.json({ success: true, message: 'User and associated attendance records deleted' });
    } catch (error) {
        res.status(500).json({ success: false, message: 'Server error', error: error.message });
    }
};