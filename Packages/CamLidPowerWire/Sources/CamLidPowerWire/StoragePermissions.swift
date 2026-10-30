import Darwin

/// Unix mode bits alone do not rule out an ACL granting another user write access.
/// Local trust storage deliberately supports only paths with no extended ACL.
public func requireNoExtendedACL(fd: Int32) throws {
    guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
        guard errno == ENOENT else { throw HelperIdentityFailure.invalidIdentity }
        return
    }
    acl_free(UnsafeMutableRawPointer(acl))
    throw HelperIdentityFailure.invalidIdentity
}
