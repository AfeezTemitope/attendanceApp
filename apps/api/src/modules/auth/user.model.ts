import { Schema, model } from 'mongoose';

export interface User {
  email: string;
  name: string;
  passwordHash: string;
  lastLoginAt?: Date;
}

const userSchema = new Schema<User>(
  {
    email: { type: String, required: true, unique: true, lowercase: true, trim: true, maxlength: 254 },
    name: { type: String, required: true, trim: true, maxlength: 120 },
    passwordHash: { type: String, required: true, select: false },
    lastLoginAt: { type: Date },
  },
  { timestamps: true },
);

export const UserModel = model<User>('User', userSchema);
