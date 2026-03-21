from rest_framework.permissions import BasePermission


class IsPassenger(BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == "passenger"


class IsDriver(BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == "driver"


class IsApprovedDriver(BasePermission):
    message = "Votre compte chauffeur n'est pas encore approuvé. Veuillez patienter pendant la vérification de vos documents."

    def has_permission(self, request, view):
        if not (request.user.is_authenticated and request.user.role == "driver"):
            return False
        if not hasattr(request.user, "driver_profile"):
            return False
        profile = request.user.driver_profile
        if profile.status == "pending":
            self.message = "Votre compte est en cours de vérification. Vous serez notifié une fois approuvé."
        elif profile.status == "rejected":
            reason = profile.rejection_reason or "Non spécifiée"
            self.message = f"Votre compte a été rejeté. Raison : {reason}"
        elif profile.status == "suspended":
            self.message = "Votre compte a été suspendu. Contactez le support pour plus d'informations."
        return profile.status == "approved"


class IsAdmin(BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and (
            request.user.role == "admin" or request.user.is_staff
        )
