import {Routes, Route, Navigate} from 'react-router-dom'
import Home from "./component/Home.jsx";
import AdminLogin from "./component/AdminLogin.jsx";
import AdminRegister from "./component/AdminRegister.jsx";
import MarkAttendance from "./component/MarkAttendance.jsx";
import UserList from "./component/UserList.jsx";

const ProtectedRoute = ({ children }) => {
    const token = localStorage.getItem('adminToken');
    return token ? children : <Navigate to="/admin/login" />;
};

const App = () => {
    return(
        <Routes>
            <Route path={'/'} element={<Navigate to='/admin/login'/>} />
            <Route path="/admin/login" element={<AdminLogin />} />
            <Route path="/admin/register" element={<AdminRegister />} />
            <Route path="/attendance" element={
                <ProtectedRoute>
                    <MarkAttendance />
                </ProtectedRoute>
            } />
            <Route
                path="/admin"
                element={
                    <ProtectedRoute>
                        <UserList />
                    </ProtectedRoute>
                }
            />
        </Routes>
    )
}

export default App