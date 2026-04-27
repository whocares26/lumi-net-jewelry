#pragma once
#include <string>

namespace JwtUtils {
    // Creates a JWT token with user info payload
    std::string createToken(
        int userId,
        const std::string& role,
        const std::string& refId   // snils or client_id as string
    );

    // Verifies token and extracts payload; returns false if invalid/expired
    bool verifyToken(
        const std::string& token,
        int&         outUserId,
        std::string& outRole,
        std::string& outRefId
    );
}
