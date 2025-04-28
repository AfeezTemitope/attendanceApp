import React, { useState, useEffect } from 'react';
import {
    Box,
    Heading,
    Switch,
    Button,
    Input,
    Table,
    Thead,
    Tbody,
    Tr,
    Th,
    Td,
    FormControl,
    FormLabel,
    useToast,
    Flex,
    Spinner,
} from '@chakra-ui/react';
import { keyframes } from '@emotion/react';
import { motion } from 'framer-motion';
import axios from 'axios';
import { useNavigate } from 'react-router-dom';

// Custom animation for button bounce
const bounce = keyframes`
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-5px); }
`;

// Custom toast styles
const toastStyles = {
    container: {
        borderRadius: '12px',
        bg: 'rgba(255, 255, 255, 0.9)',
        boxShadow: '0 4px 12px rgba(0, 0, 0, 0.1)',
        backdropFilter: 'blur(10px)',
    },
    title: {
        fontWeight: 'bold',
        color: '#4A5568',
    },
    description: {
        color: '#718096',
    },
};

const UserList = () => {
    const [users, setUsers] = useState([]);
    const [name, setName] = useState('');
    const [userCode, setUserCode] = useState('');
    const [editId, setEditId] = useState(null);
    const [showCodes, setShowCodes] = useState(true);
    const [sortOrder, setSortOrder] = useState('asc');
    const [isLoading, setIsLoading] = useState(false);
    const toast = useToast();
    const navigate = useNavigate();

    const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

    useEffect(() => {
        const token = localStorage.getItem('adminToken');
        if (!token) {
            toast({
                title: 'Unauthorized',
                description: 'Please log in to access this page.',
                status: 'error',
                duration: 5000,
                isClosable: true,
                position: 'top',
                containerStyle: toastStyles.container,
                titleStyle: toastStyles.title,
                descriptionStyle: toastStyles.description,
            });
            navigate('/admin/login');
        } else {
            fetchUsers();
        }
    }, [navigate, toast]);

    const fetchUsers = async () => {
        const token = localStorage.getItem('adminToken');
        console.log('Fetching users with token:', token);
        if (!token) return;

        try {
            const config = {
                headers: { Authorization: `Bearer ${token}` },
            };
            console.log('Request headers:', config);
            const res = await axios.get('http://localhost:5000/api/admin/users', config);
            console.log('Fetch users response:', res.data); // Debug log
            // Handle different response structures
            const usersData = Array.isArray(res.data)
                ? res.data
                : res.data.data && Array.isArray(res.data.data)
                    ? res.data.data
                    : [];
            setUsers(usersData);
        } catch (err) {
            console.error('Fetch users error:', err.response?.data || err.message);
            const errorMessage = err.response?.data?.message || 'Failed to fetch users.';
            if (err.response?.status === 401) {
                toast({
                    title: 'Unauthorized',
                    description: errorMessage,
                    status: 'error',
                    duration: 5000,
                    isClosable: true,
                    position: 'top',
                    containerStyle: toastStyles.container,
                    titleStyle: toastStyles.title,
                    descriptionStyle: toastStyles.description,
                });
                localStorage.removeItem('adminToken');
                navigate('/admin/login');
            } else {
                toast({
                    title: 'Error fetching users.',
                    description: errorMessage,
                    status: 'error',
                    duration: 5000,
                    isClosable: true,
                    position: 'top',
                    containerStyle: toastStyles.container,
                    titleStyle: toastStyles.title,
                    descriptionStyle: toastStyles.description,
                });
            }
        }
    };

    const handleAddOrUpdateUser = async () => {
        const token = localStorage.getItem('adminToken');
        if (!token) {
            toast({
                title: 'Unauthorized',
                description: 'Please log in to perform this action.',
                status: 'error',
                duration: 5000,
                isClosable: true,
                position: 'top',
                containerStyle: toastStyles.container,
                titleStyle: toastStyles.title,
                descriptionStyle: toastStyles.description,
            });
            navigate('/admin/login');
            return;
        }

        setIsLoading(true);
        try {
            const config = {
                headers: { Authorization: `Bearer ${token}` },
            };
            console.log('Add/Update user headers:', config);
            let res;
            if (editId) {
                const serverRequest = axios.put(`http://localhost:5000/api/admin/users/${editId}`, { name, userCode }, config);
                [res] = await Promise.all([serverRequest, delay(2000)]);
                setUsers(users.map((user) => (user._id === editId ? res.data : user)));
                toast({
                    title: 'User updated.',
                    description: 'User information has been updated successfully.',
                    status: 'success',
                    duration: 5000,
                    isClosable: true,
                    position: 'top',
                    containerStyle: toastStyles.container,
                    titleStyle: toastStyles.title,
                    descriptionStyle: toastStyles.description,
                });
                setEditId(null);
            } else {
                const serverRequest = axios.post('http://localhost:5000/api/admin/users', { name, userCode }, config);
                [res] = await Promise.all([serverRequest, delay(2000)]);
                setUsers([...users, res.data]);
                toast({
                    title: 'User added.',
                    description: 'New user has been added successfully.',
                    status: 'success',
                    duration: 5000,
                    isClosable: true,
                    position: 'top',
                    containerStyle: toastStyles.container,
                    titleStyle: toastStyles.title,
                    descriptionStyle: toastStyles.description,
                });
            }
            setName('');
            setUserCode('');
        } catch (err) {
            console.error('Add/Update user error:', err.response?.data || err.message);
            const errorMessage = err.response?.data?.message || 'Failed to add/update user.';
            if (err.response?.status === 401) {
                toast({
                    title: 'Unauthorized',
                    description: errorMessage,
                    status: 'error',
                    duration: 5000,
                    isClosable: true,
                    position: 'top',
                    containerStyle: toastStyles.container,
                    titleStyle: toastStyles.title,
                    descriptionStyle: toastStyles.description,
                });
                localStorage.removeItem('adminToken');
                navigate('/admin/login');
            } else {
                toast({
                    title: 'Error adding/updating user.',
                    description: errorMessage,
                    status: 'error',
                    duration: 5000,
                    isClosable: true,
                    position: 'top',
                    containerStyle: toastStyles.container,
                    titleStyle: toastStyles.title,
                    descriptionStyle: toastStyles.description,
                });
            }
        } finally {
            setIsLoading(false);
        }
    };

    const handleEdit = (user) => {
        setEditId(user._id);
        setName(user.name);
        setUserCode(user.userCode);
    };

    const handleDelete = async (id) => {
        const token = localStorage.getItem('adminToken');
        if (!token) {
            toast({
                title: 'Unauthorized',
                description: 'Please log in to perform this action.',
                status: 'error',
                duration: 5000,
                isClosable: true,
                position: 'top',
                containerStyle: toastStyles.container,
                titleStyle: toastStyles.title,
                descriptionStyle: toastStyles.description,
            });
            navigate('/admin/login');
            return;
        }

        setIsLoading(true);
        try {
            const config = {
                headers: { Authorization: `Bearer ${token}` },
            };
            console.log('Delete user headers:', config);
            const serverRequest = axios.delete(`http://localhost:5000/api/admin/users/${id}`, config);
            await Promise.all([serverRequest, delay(2000)]);
            setUsers(users.filter((user) => user._id !== id));
            toast({
                title: 'User deleted.',
                description: 'User has been removed successfully.',
                status: 'success',
                duration: 5000,
                isClosable: true,
                position: 'top',
                containerStyle: toastStyles.container,
                titleStyle: toastStyles.title,
                descriptionStyle: toastStyles.description,
            });
        } catch (err) {
            console.error('Delete user error:', err.response?.data || err.message);
            const errorMessage = err.response?.data?.message || 'Failed to delete user.';
            if (err.response?.status === 401) {
                toast({
                    title: 'Unauthorized',
                    description: errorMessage,
                    status: 'error',
                    duration: 5000,
                    isClosable: true,
                    position: 'top',
                    containerStyle: toastStyles.container,
                    titleStyle: toastStyles.title,
                    descriptionStyle: toastStyles.description,
                });
                localStorage.removeItem('adminToken');
                navigate('/admin/login');
            } else {
                toast({
                    title: 'Error deleting user.',
                    description: errorMessage,
                    status: 'error',
                    duration: 5000,
                    isClosable: true,
                    position: 'top',
                    containerStyle: toastStyles.container,
                    titleStyle: toastStyles.title,
                    descriptionStyle: toastStyles.description,
                });
            }
        } finally {
            setIsLoading(false);
        }
    };

    const handleSortByName = () => {
        const newSortOrder = sortOrder === 'asc' ? 'desc' : 'asc';
        setSortOrder(newSortOrder);
        const sortedUsers = [...users].sort((a, b) => {
            const nameA = a.name.toLowerCase();
            const nameB = b.name.toLowerCase();
            return newSortOrder === 'asc' ? (nameA < nameB ? -1 : 1) : (nameA > nameB ? -1 : 1);
        });
        setUsers(sortedUsers);
    };

    return (
        <Flex
            minH="100vh"
            bgGradient="linear(to-br, pink.200, purple.300, blue.200)"
            position="relative"
            overflow="hidden"
            justify="center"
            align="center"
            p={4}
        >
            <Box
                as="svg"
                position="absolute"
                bottom="0"
                left="0"
                width="100%"
                height="30%"
                viewBox="0 0 1440 320"
                preserveAspectRatio="none"
                opacity="0.3"
            >
                <path
                    fill="#ffffff"
                    fillOpacity="0.5"
                    d="M0,192L48,186.7C96,181,192,171,288,181.3C384,192,480,224,576,213.3C672,203,768,149,864,138.7C960,128,1056,160,1152,176C1248,192,1344,192,1392,192L1440,192L1440,320L1392,320C1344,320,1248,320,1152,320C1056,320,960,320,864,320C768,320,672,320,576,320C480,320,384,320,288,320C192,320,96,320,48,320L0,320Z"
                >
                    <animate
                        attributeName="d"
                        dur="10s"
                        repeatCount="indefinite"
                        values="
                            M0,192L48,186.7C96,181,192,171,288,181.3C384,192,480,224,576,213.3C672,203,768,149,864,138.7C960,128,1056,160,1152,176C1248,192,1344,192,1392,192L1440,192L1440,320L1392,320C1344,320,1248,320,1152,320C1056,320,960,320,864,320C768,320,672,320,576,320C480,320,384,320,288,320C192,320,96,320,48,320L0,320Z;
                            M0,160L48,176C96,192,192,224,288,213.3C384,203,480,149,576,138.7C672,128,768,160,864,176C960,192,1056,192,1152,192C1248,192,1344,192,1392,192L1440,192L1440,320L1392,320C1344,320,1248,320,1152,320C1056,320,960,320,864,320C768,320,672,320,576,320C480,320,384,320,288,320C192,320,96,320,48,320L0,320Z;
                            M0,192L48,186.7C96,181,192,171,288,181.3C384,192,480,224,576,213.3C672,203,768,149,864,138.7C960,128,1056,160,1152,176C1248,192,1344,192,1392,192L1440,192L1440,320L1392,320C1344,320,1248,320,1152,320C1056,320,960,320,864,320C768,320,672,320,576,320C480,320,384,320,288,320C192,320,96,320,48,320L0,320Z"
                    />
                </path>
            </Box>

            <Box
                as={motion.div}
                initial={{ scale: 0.8, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{ duration: 0.5 }}
                maxW="lg"
                w="full"
                p={8}
                bg="rgba(255, 255, 255, 0.85)"
                borderRadius="2xl"
                boxShadow="xl"
                backdropFilter="blur(12px)"
                border="1px solid rgba(255, 255, 255, 0.3)"
            >
                <Flex justify="center" mb={4}>
                    <Box
                        as="svg"
                        width="64px"
                        height="64px"
                        viewBox="0 0 24 24"
                        fill="none"
                        xmlns="http://www.w3.org/2000/svg"
                    >
                        <path
                            d="M12 21C16.9706 21 21 16.9706 21 12C21 7.02944 16.9706 3 12 3C7.02944 3 3 7.02944 3 12C3 16.9706 7.02944 21 12 21Z"
                            stroke="#FF6B6B"
                            strokeWidth="2"
                        />
                        <path
                            d="M8 12H16"
                            stroke="#FF6B6B"
                            strokeWidth="2"
                            strokeLinecap="round"
                        />
                        <path
                            d="M12 8V16"
                            stroke="#FF6B6B"
                            strokeWidth="2"
                            strokeLinecap="round"
                        />
                        <animateTransform
                            attributeName="transform"
                            type="rotate"
                            from="0 12 12"
                            to="360 12 12"
                            dur="5s"
                            repeatCount="indefinite"
                        />
                    </Box>
                </Flex>

                <Heading
                    size="lg"
                    mb={6}
                    textAlign="center"
                    fontFamily="'Poppins', sans-serif"
                    bgGradient="linear(to-r, pink.400, purple.500)"
                    bgClip="text"
                >
                    User List
                </Heading>

                <Box mb={6}>
                    <FormControl mb={5}>
                        <FormLabel fontFamily="'Poppins', sans-serif" color="gray.600">
                            Name
                        </FormLabel>
                        <Input
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            placeholder="Enter user name"
                            bg="white"
                            borderRadius="full"
                            border="1px solid"
                            borderColor="gray.200"
                            _focus={{
                                borderColor: 'pink.400',
                                boxShadow: '0 0 0 3px rgba(255, 107, 107, 0.2)',
                            }}
                            _hover={{ borderColor: 'pink.300' }}
                            fontFamily="'Poppins', sans-serif"
                            transition="all 0.3s"
                        />
                    </FormControl>
                    <FormControl mb={5}>
                        <FormLabel fontFamily="'Poppins', sans-serif" color="gray.600">
                            User Code
                        </FormLabel>
                        <Input
                            value={userCode}
                            onChange={(e) => setUserCode(e.target.value)}
                            placeholder="Enter user code"
                            bg="white"
                            borderRadius="full"
                            border="1px solid"
                            borderColor="gray.200"
                            _focus={{
                                borderColor: 'pink.400',
                                boxShadow: '0 0 0 3px rgba(255, 107, 107, 0.2)',
                            }}
                            _hover={{ borderColor: 'pink.300' }}
                            fontFamily="'Poppins', sans-serif"
                            transition="all 0.3s"
                        />
                    </FormControl>
                    <Button
                        as={motion.button}
                        whileHover={{ scale: 1.05, animation: `${bounce} 0.3s` }}
                        whileTap={{ scale: 0.95 }}
                        colorScheme="pink"
                        width="full"
                        borderRadius="full"
                        bgGradient="linear(to-r, pink.400, purple.500)"
                        _hover={{ bgGradient: 'linear(to-r, pink.500, purple.600)' }}
                        fontFamily="'Poppins', sans-serif"
                        fontWeight="bold"
                        onClick={handleAddOrUpdateUser}
                        isDisabled={isLoading || !name.trim() || !userCode.trim()}
                        aria-label={editId ? 'Update User' : 'Add User'}
                    >
                        {isLoading ? <Spinner size="sm" color="white" /> : editId ? 'Update User' : 'Add User'}
                    </Button>
                </Box>

                <FormControl display="flex" alignItems="center" mb={5}>
                    <FormLabel
                        htmlFor="show-codes"
                        mb="0"
                        fontFamily="'Poppins', sans-serif"
                        color="gray.600"
                    >
                        Show User Codes
                    </FormLabel>
                    <Switch
                        id="show-codes"
                        isChecked={showCodes}
                        onChange={(e) => setShowCodes(e.target.checked)}
                        colorScheme="pink"
                    />
                </FormControl>

                <Box overflowX="auto" borderRadius="lg" bg="white" p={3} boxShadow="sm">
                    <Table variant="simple">
                        <Thead>
                            <Tr>
                                <Th fontFamily="'Poppins', sans-serif" color="gray.600">
                                    <Button
                                        as={motion.button}
                                        whileHover={{ scale: 1.05 }}
                                        whileTap={{ scale: 0.95 }}
                                        variant="ghost"
                                        size="sm"
                                        onClick={handleSortByName}
                                        rightIcon={<span>{sortOrder === 'asc' ? '↑' : '↓'}</span>}
                                        fontFamily="'Poppins', sans-serif"
                                        color="purple.500"
                                        _hover={{ color: 'purple.600' }}
                                    >
                                        Name
                                    </Button>
                                </Th>
                                {showCodes && (
                                    <Th fontFamily="'Poppins', sans-serif" color="gray.600">
                                        User Code
                                    </Th>
                                )}
                                <Th fontFamily="'Poppins', sans-serif" color="gray.600">
                                    Actions
                                </Th>
                            </Tr>
                        </Thead>
                        <Tbody>
                            {users.map((user) => (
                                <Tr
                                    key={user._id}
                                    _hover={{ bg: 'pink.50' }}
                                    transition="all 0.2s"
                                >
                                    <Td fontFamily="'Poppins', sans-serif" color="black">
                                        {user.name}
                                    </Td>
                                    {showCodes && (
                                        <Td fontFamily="'Poppins', sans-serif" color="black">
                                            {user.userCode}
                                        </Td>
                                    )}
                                    <Td>
                                        <Button
                                            as={motion.button}
                                            whileHover={{ scale: 1.05 }}
                                            whileTap={{ scale: 0.95 }}
                                            size="sm"
                                            colorScheme="pink"
                                            mr={2}
                                            onClick={() => handleEdit(user)}
                                            isDisabled={isLoading}
                                            aria-label="Edit User"
                                            borderRadius="full"
                                            bgGradient="linear(to-r, pink.400, purple.500)"
                                            _hover={{ bgGradient: 'linear(to-r, pink.500, purple.600)' }}
                                            fontFamily="'Poppins', sans-serif"
                                        >
                                            {isLoading ? <Spinner size="sm" color="white" /> : 'Edit'}
                                        </Button>
                                        <Button
                                            as={motion.button}
                                            whileHover={{ scale: 1.05 }}
                                            whileTap={{ scale: 0.95 }}
                                            size="sm"
                                            colorScheme="purple"
                                            onClick={() => handleDelete(user._id)}
                                            isDisabled={isLoading}
                                            aria-label="Delete User"
                                            borderRadius="full"
                                            bg="purple.500"
                                            _hover={{ bg: 'purple.600' }}
                                            fontFamily="'Poppins', sans-serif"
                                        >
                                            {isLoading ? <Spinner size="sm" color="white" /> : 'Delete'}
                                        </Button>
                                    </Td>
                                </Tr>
                            ))}
                        </Tbody>
                    </Table>
                </Box>
            </Box>
        </Flex>
    );
};

export default UserList;