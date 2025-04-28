import React, { useState, useEffect } from 'react';
import {
    Box,
    Heading,
    Button,
    Input,
    FormControl,
    FormLabel,
    useToast,
    Flex,
    Text,
    Icon,
    Spinner,
} from '@chakra-ui/react';
import { keyframes } from '@emotion/react';
import { FaCircle } from 'react-icons/fa';
import { Link } from 'react-router-dom';
import { motion } from 'framer-motion';
import axios from 'axios';

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

const MarkAttendance = () => {
    const [userCode, setUserCode] = useState('');
    const [attendees, setAttendees] = useState([]);
    const [markedCodes, setMarkedCodes] = useState(new Set());
    const [isLoading, setIsLoading] = useState(false);
    const [isAdminAuthenticated, setIsAdminAuthenticated] = useState(!!localStorage.getItem('adminToken'));
    const toast = useToast();

    const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

    // Fetch users for the authenticated admin
    useEffect(() => {
        const fetchAttendees = async () => {
            try {
                const token = localStorage.getItem('adminToken');
                if (!token) {
                    throw new Error('No admin token found. Please log in.');
                }
                const res = await axios.get('/api/admin/users', {
                    headers: { Authorization: `Bearer ${token}` },
                });
                setAttendees(res.data);
                if (res.data.length === 0) {
                    toast({
                        title: 'No Users Found',
                        description: 'No users are associated with this admin. Add users to proceed.',
                        status: 'info',
                        duration: 5000,
                        isClosable: true,
                        position: 'top',
                        containerStyle: toastStyles.container,
                        titleStyle: toastStyles.title,
                        descriptionStyle: toastStyles.description,
                    });
                }
            } catch (err) {
                toast({
                    title: 'Fetch Failed',
                    description: err.response?.data.message || err.message || 'Failed to fetch attendees.',
                    status: 'error',
                    duration: 5000,
                    isClosable: true,
                    position: 'top',
                    containerStyle: toastStyles.container,
                    titleStyle: toastStyles.title,
                    descriptionStyle: toastStyles.description,
                });
            }
        };
        if (isAdminAuthenticated) {
            fetchAttendees();
        }
    }, [toast, isAdminAuthenticated]);

    const handleMarkAttendance = async () => {
        if (!userCode.trim()) {
            toast({
                title: 'Invalid Input',
                description: 'User code is required.',
                status: 'warning',
                duration: 5000,
                isClosable: true,
                position: 'top',
                containerStyle: toastStyles.container,
                titleStyle: toastStyles.title,
                descriptionStyle: toastStyles.description,
            });
            return;
        }

        setIsLoading(true);

        try {
            const token = localStorage.getItem('adminToken');
            if (!token) {
                throw new Error('No admin token found. Please log in.');
            }
            const serverRequest = axios.post(
                '/api/attendance',
                { userCode },
                { headers: { Authorization: `Bearer ${token}` } }
            );
            const [res] = await Promise.all([serverRequest, delay(2000)]);

            setMarkedCodes((prev) => new Set([...prev, userCode]));
            toast({
                title: 'Attendance Marked',
                description: 'Attendance marked successfully.',
                status: 'success',
                duration: 5000,
                isClosable: true,
                position: 'top',
                containerStyle: toastStyles.container,
                titleStyle: toastStyles.title,
                descriptionStyle: toastStyles.description,
            });
            setUserCode('');
        } catch (err) {
            toast({
                title: 'Attendance Failed',
                description: err.response?.data.message || 'Failed to mark attendance.',
                status: 'error',
                duration: 5000,
                isClosable: true,
                position: 'top',
                containerStyle: toastStyles.container,
                titleStyle: toastStyles.title,
                descriptionStyle: toastStyles.description,
            });
        } finally {
            setIsLoading(false);
        }
    };

    return (
        <Flex
            direction="column"
            minH="100vh"
            bgGradient="linear(to-br, pink.200, purple.300, blue.200)"
            position="relative"
            overflow="hidden"
        >
            {/* Animated background wave */}
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
                flex="1"
                display="flex"
                alignItems="center"
                justifyContent="center"
                p={4}
            >
                <Box
                    as={motion.div}
                    initial={{ scale: 0.8, opacity: 0 }}
                    animate={{ scale: 1, opacity: 1 }}
                    transition={{ duration: 0.5 }}
                    maxW="sm"
                    w="full"
                    p={8}
                    bg="rgba(255, 255, 255, 0.85)"
                    borderRadius="2xl"
                    boxShadow="xl"
                    backdropFilter="blur(12px)"
                    border="1px solid rgba(255, 255, 255, 0.3)"
                >
                    {/* Cute logo/icon */}
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
                        Mark Attendance
                    </Heading>

                    <Box mb={6}>
                        <FormControl mb={5} isRequired>
                            <FormLabel fontFamily="'Poppins', sans-serif" color="gray.600">
                                User Code
                            </FormLabel>
                            <Input
                                value={userCode}
                                onChange={(e) => setUserCode(e.target.value.trim())}
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
                            onClick={handleMarkAttendance}
                            isDisabled={isLoading || !userCode.trim()}
                            aria-label="Mark Attendance"
                        >
                            {isLoading ? <Spinner size="sm" color="white" /> : 'Mark Attendance'}
                        </Button>
                    </Box>

                    <Box>
                        <Heading
                            size="md"
                            mb={4}
                            fontFamily="'Poppins', sans-serif"
                            color="gray.600"
                        >
                            Attendees
                        </Heading>
                        {attendees.length > 0 ? (
                            <Box
                                maxH="300px"
                                overflowY="auto"
                                borderRadius="lg"
                                bg="white"
                                p={3}
                                boxShadow="sm"
                                border="1px solid"
                                borderColor="gray.100"
                            >
                                {attendees.map((attendee) => (
                                    <Flex
                                        key={attendee.userCode}
                                        align="center"
                                        py={2}
                                        px={3}
                                        borderBottomWidth={1}
                                        borderColor="gray.100"
                                        _last={{ borderBottomWidth: 0 }}
                                        bg={markedCodes.has(attendee.userCode) ? 'pink.50' : 'transparent'}
                                        borderRadius="md"
                                        _hover={{ bg: 'pink.100' }}
                                        transition="all 0.2s"
                                    >
                                        <Icon
                                            as={FaCircle}
                                            color={markedCodes.has(attendee.userCode) ? 'pink.500' : 'purple.500'}
                                            mr={3}
                                            boxSize={3}
                                        />
                                        <Text
                                            fontSize="sm"
                                            fontFamily="'Poppins', sans-serif"
                                            color="gray.700"
                                        >
                                            {attendee.name} ({attendee.userCode})
                                        </Text>
                                    </Flex>
                                ))}
                            </Box>
                        ) : (
                            <Text
                                fontSize="sm"
                                fontFamily="'Poppins', sans-serif"
                                color="gray.500"
                            >
                                No attendees found.
                            </Text>
                        )}
                    </Box>
                </Box>
            </Box>

            {isAdminAuthenticated && (
                <Box
                    as="footer"
                    py={4}
                    bg="rgba(255, 255, 255, 0.85)"
                    backdropFilter="blur(12px)"
                    textAlign="center"
                    borderTop="1px solid rgba(255, 255, 255, 0.3)"
                >
                    <Text
                        as={Link}
                        to="/admin"
                        fontSize="sm"
                        fontFamily="'Poppins', sans-serif"
                        color="purple.500"
                        _hover={{ color: 'purple.600', textDecoration: 'underline' }}
                    >
                        Attendance Sheet
                    </Text>
                </Box>
            )}
        </Flex>
    );
};

export default MarkAttendance;