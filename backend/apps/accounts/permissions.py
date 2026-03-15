from rest_framework.permissions import BasePermission


class IsPassenger(BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == "passenger"


class IsDriver(BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == "driver"


class IsApprovedDriver(BasePermission):
    def has_permission(self, request, view):
        if not (request.user.is_authenticated and request.user.role == "driver"):
            return False
        return hasattr(request.user, "driver_profile") and (
            request.user.driver_profile.status == "approved"
        )


class IsAdmin(BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and (
            request.user.role == "admin" or request.user.is_staff
        )
