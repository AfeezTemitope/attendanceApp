import mongoose from 'mongoose';

const userSchema = new mongoose.Schema({
    name: {
        type: String,
        required: true,
    },
    userCode: {
        type: String,
        required: true,
    },
    admin: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Admin',
        required: true,
    },
});

userSchema.index({ admin: 1, name: 1 }, { unique: true });
userSchema.index({ admin: 1, userCode: 1 }, { unique: true });

export default mongoose.model('User', userSchema);