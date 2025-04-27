import User from '../models/User.js';

export const validateUserCode = async (req, res) => {
    const { userCode } = req.body;
    if (!userCode) {
        return res.status(400).json({ success: false, message: 'User code is required' });
    }

    try {
        const user = await User.findOne({ userCode }).select('name admin');
        if (!user) {
            return res.status(400).json({ success: false, message: 'Invalid user code' });
        }

        res.json({ success: true, data: { name: user.name, admin: user.admin } });
    } catch (error) {
        res.status(500).json({ success: false, message: 'Server error', error: error.message });
    }
};