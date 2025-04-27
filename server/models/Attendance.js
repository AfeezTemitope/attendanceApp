import mongoose from 'mongoose';

const AttendanceSchema = new mongoose.Schema({
    name: { type: String, required: true },
    admin: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin', required: true },
    date: { type: Date, default: Date.now },
});

export default mongoose.model('Attendance', AttendanceSchema);