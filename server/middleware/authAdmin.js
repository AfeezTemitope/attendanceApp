import jwt from 'jsonwebtoken';

const authAdmin = (req, res, next) => {
    console.log('Raw headers:', req.headers);
    const authHeader = req.header('Authorization') || req.header('authorization');
    if (!authHeader) {
        return res.status(401).json({ message: 'No token, authorization denied' });
    }
    const token = authHeader.replace('Bearer ', '').trim();
    if (!token) {
        return res.status(401).json({ message: 'No token, authorization denied' });
    }
    try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET_ADMIN);
        req.admin = decoded;
        next();
    } catch (err) {
        res.status(401).json({ message: 'Invalid token' });
    }
};

export default authAdmin